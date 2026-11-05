import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthSecrets {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeystoreAuthSecrets implements AuthSecrets {
  const KeystoreAuthSecrets();
  static const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'mobile_auth_v1',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

abstract interface class AuthGate {
  Future<T> run<T>(Future<T> Function() action);
}

/// SQLite's native exclusive transaction is shared across Flutter engines and
/// processes. The database contains NO session data: it is only a mutex. Do not
/// replace with a Dart mutex or POSIX process-owned file locks across isolates.
class SqliteAuthGate implements AuthGate {
  SqliteAuthGate({this.name = 'mobile_auth_gate_v1'});
  final String name;
  Future<Database>? _database;
  Future<Database> _open() async => databaseFactory.openDatabase(
    '${await getDatabasesPath()}/$name.db',
    options: OpenDatabaseOptions(
      version: 1,
      singleInstance: true,
      // A second engine must not hot-restart-rollback a live transaction.
      rollbackActiveTransactionOnOpen: false,
      // A second engine can open while a bounded Auth request holds the gate.
      // Configure before sqflite reads user_version/starts its transaction;
      // otherwise a separate native SQLite connection can fail immediately.
      onConfigure: (db) => db.execute('PRAGMA busy_timeout = 35000'),
      onCreate: (db, _) =>
          db.execute('CREATE TABLE gate (id INTEGER PRIMARY KEY)'),
    ),
  );
  @override
  Future<T> run<T>(Future<T> Function() action) async {
    final database = await (_database ??= _open());
    return database.transaction((_) => action(), exclusive: true);
  }
}

/// The one durable Auth authority. SDK event persistence is deliberately read
/// only: HTTP login/refresh commits under the same gate before the SDK sees its
/// response. Late SDK callbacks therefore cannot resurrect a logged-out session.
/// A random login epoch distinguishes even logout/relogin of the same account.
class SecureSessionVault extends LocalStorage {
  SecureSessionVault({
    required this.secrets,
    required this.gate,
    this.projectOrigin = 'https://supabase.firesideafrica.cloud',
  });
  factory SecureSessionVault.production({
    String projectOrigin = 'https://supabase.firesideafrica.cloud',
  }) => SecureSessionVault(
    projectOrigin: projectOrigin,
    secrets: const KeystoreAuthSecrets(),
    gate: SqliteAuthGate(),
  );
  final String projectOrigin;
  String get sessionKey =>
      'supabase_session_v1_${sha256.convert(utf8.encode(projectOrigin))}';
  final AuthSecrets secrets;
  final AuthGate gate;
  String? _epoch;
  String? get binding => _epoch;

  Future<Map<String, dynamic>?> _read() async {
    final raw = await secrets.read(sessionKey);
    if (raw == null) return null;
    final record = _decodeObject(raw);
    if (record['epoch'] is! String ||
        (record['session'] != null &&
            record['session'] is! Map<String, dynamic>)) {
      throw StateError('Secure authentication unavailable.');
    }
    return record;
  }

  Map<String, dynamic> _session(Map<String, dynamic> record) =>
      record['session'] as Map<String, dynamic>;

  Future<void> _commit(String epoch, Map<String, dynamic> session) async {
    if (session['access_token'] is! String ||
        session['refresh_token'] is! String ||
        (session['user'] as Map?)?['id'] is! String) {
      throw StateError('Invalid authenticated session.');
    }
    final normalized = Map<String, dynamic>.from(session);
    if (normalized['expires_at'] == null && normalized['expires_in'] is num) {
      normalized['expires_at'] =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          (normalized['expires_in'] as num).toInt();
    }
    await secrets.write(
      sessionKey,
      jsonEncode({'epoch': epoch, 'session': normalized}),
    );
  }

  String _newEpoch() =>
      base64Url.encode(List.generate(24, (_) => Random.secure().nextInt(256)));
  Future<String?> currentEpoch() =>
      gate.run(() async => (await _read())?['epoch'] as String?);
  Future<void> acceptLogin(
    Map<String, dynamic> session, {
    String? expectedEpoch,
    bool guarded = false,
  }) => gate.run(() async {
    if (guarded && (await _read())?['epoch'] != expectedEpoch) {
      throw StateError('Authentication operation superseded.');
    }
    final epoch = _newEpoch();
    await _commit(epoch, session);
    _epoch = epoch;
  });

  /// Exchange the portal-issued refresh token without exposing it to SDK
  /// persistence. Preserve the original epoch across both network hops.
  Future<void> acceptPortalLogin(
    http.Client transport,
    Uri origin,
    String anonKey,
    String refreshToken,
    String email, {
    String? expectedEpoch,
  }) async {
    if (await currentEpoch() != expectedEpoch) {
      throw StateError('Authentication operation superseded.');
    }
    final request =
        http.Request(
            'POST',
            origin.resolve('/auth/v1/token?grant_type=refresh_token'),
          )
          ..followRedirects = false
          ..headers.addAll({
            'apikey': anonKey,
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({'refresh_token': refreshToken});
    final response = await _send(transport, request);
    if (response.statusCode != 200) {
      throw StateError('Authentication refresh unavailable.');
    }
    final session = _decodeObject(response.body);
    final user = session['user'];
    if (user is! Map ||
        user['email'] is! String ||
        (user['email'] as String).toLowerCase() != email.toLowerCase()) {
      throw StateError('Authentication identity changed.');
    }
    await acceptLogin(session, expectedEpoch: expectedEpoch, guarded: true);
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<String?> accessToken() => gate.run(() async {
    final record = await _read();
    _epoch = record?['epoch'] as String?;
    return record == null || record['session'] == null
        ? null
        : jsonEncode(_session(record));
  });
  @override
  Future<void> persistSession(String persistSessionString) async {
    // The transport already committed. Never trust asynchronous SDK callbacks.
  }
  @override
  Future<void> removePersistedSession() {
    final expected = _epoch;
    _epoch = null;
    return gate.run(() async {
      if ((await _read())?['epoch'] == expected) {
        await secrets.write(
          sessionKey,
          jsonEncode({'epoch': _newEpoch(), 'session': null}),
        );
      }
    });
  }

  Future<bool> isCurrent(String epoch) =>
      gate.run(() async => (await _read())?['epoch'] == epoch);

  Future<void> whileCurrent(String epoch, Future<void> Function() action) =>
      gate.run(() async {
        if (_epoch != epoch || (await _read())?['epoch'] != epoch) {
          throw StateError('Update identity changed.');
        }
        await action();
      });

  /// Removes rather than imports the SDK's old plaintext persistence. A one-time
  /// sign-in is preferable to enrolling credentials from an untrusted old copy.
  Future<void> removeLegacyPlaintext(Uri origin) async {
    // The SDK used legacy SharedPreferences XML, whereas Async defaults to
    // Android DataStore. Remove both backends without reading/copying secrets.
    final legacy = await SharedPreferences.getInstance();
    final prefs = SharedPreferencesAsync();
    for (final key in [
      'sb-${origin.host.split('.').first}-auth-token',
      'supabase.auth.token-code-verifier',
    ]) {
      await legacy.remove(key);
      await prefs.remove(key);
    }
  }

  Future<Map<String, dynamic>> freshSession(
    http.Client transport,
    Uri origin,
    String anonKey,
  ) => gate.run(() async {
    final record = await _read();
    if (record == null ||
        record['session'] == null ||
        record['epoch'] != _epoch) {
      throw StateError('Sign in to check updates.');
    }
    final expectedEpoch = _epoch;
    var session = _session(record);
    final expiry = session['expires_at'];
    if (expiry is! num ||
        expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60) {
      final request =
          http.Request(
              'POST',
              origin.resolve('/auth/v1/token?grant_type=refresh_token'),
            )
            ..followRedirects = false
            ..headers.addAll({
              'apikey': anonKey,
              'Content-Type': 'application/json',
            })
            ..body = jsonEncode({'refresh_token': session['refresh_token']});
      final response = await _send(transport, request);
      if (response.statusCode != 200) {
        if (response.statusCode == 400 ||
            response.statusCode == 401 ||
            response.statusCode == 403) {
          await secrets.write(
            sessionKey,
            jsonEncode({'epoch': _newEpoch(), 'session': null}),
          );
          _epoch = null;
        }
        throw StateError('Authentication refresh unavailable.');
      }
      session = _decodeObject(response.body);
      if (_epoch != expectedEpoch) {
        throw StateError('Authentication operation superseded.');
      }
      // Refresh must not silently become a different account.
      if ((session['user'] as Map?)?['id'] !=
          (_session(record)['user'] as Map)['id']) {
        throw StateError('Authentication identity changed.');
      }
      await _commit(record['epoch'] as String, session);
    }
    if (_epoch != expectedEpoch) {
      throw StateError('Authentication operation superseded.');
    }
    return Map<String, dynamic>.from(session);
  });

  /// This is the private eligibility route, not a Storage/download request.
  /// Signed URLs live only in the caller's memory; workers discard the result.
  Future<Map<String, dynamic>> checkPrivate(
    http.Client transport,
    Uri origin,
    String anonKey,
  ) async {
    final epoch = _epoch;
    if (epoch == null) throw StateError('Authentication unavailable.');
    final session = await freshSession(transport, origin, anonKey);
    if (_epoch != epoch || !await isCurrent(epoch)) {
      throw StateError('Update identity changed.');
    }
    final request =
        http.Request('POST', origin.resolve('/functions/v1/mobile-update'))
          ..followRedirects = false
          ..headers.addAll({
            'apikey': anonKey,
            'Authorization': 'Bearer ${session['access_token']}',
            'Content-Type': 'application/json',
          })
          ..body = '{}';
    final response = await _send(transport, request);
    if (!await isCurrent(epoch)) throw StateError('Update identity changed.');
    if (response.statusCode != 200) {
      throw StateError('Update authorization unavailable.');
    }
    final envelope = _decodeObject(response.body);
    if (!envelope.containsKey('release') ||
        (envelope['release'] != null &&
            (envelope['release'] is! Map<String, dynamic> ||
                envelope['release']['provider'] != 'supabase-rest'))) {
      throw StateError('Invalid private update response.');
    }
    return envelope;
  }
}

Map<String, dynamic> _decodeObject(String raw) {
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    throw StateError('Invalid authenticated response.');
  }
}

Future<http.Response> _send(
  http.Client client,
  http.BaseRequest request,
) async {
  try {
    return await (() async {
      const maxResponseBytes = 1024 * 1024;
      final response = await client.send(request);
      final bytes = <int>[];
      // Bound streamed bodies too, rather than trusting Content-Length. The
      // subscription is cancelled by await-for when the cap is exceeded.
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw StateError('Authenticated response too large.');
        }
        bytes.addAll(chunk);
      }
      return http.Response.bytes(
        bytes,
        response.statusCode,
        headers: response.headers,
      );
    })().timeout(const Duration(seconds: 30));
  } catch (_) {
    throw StateError('Authenticated transport unavailable.');
  }
}

/// Routes the SDK's refresh through the durable coordinator. All session-issuing
/// Auth responses are durably enrolled before delivery to the foreground SDK.
class CoordinatedAuthClient extends http.BaseClient {
  CoordinatedAuthClient(this.inner, this.vault, this.origin, this.anonKey);
  final http.Client inner;
  final SecureSessionVault vault;
  final Uri origin;
  final String anonKey;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin == origin.origin &&
        request.url.path == '/functions/v1/mobile-update') {
      final envelope = await vault.checkPrivate(inner, origin, anonKey);
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(envelope))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final isAuth =
        request.url.origin == origin.origin &&
        request.url.path.startsWith('/auth/v1/');
    if (!isAuth) return inner.send(request);
    request.followRedirects = false;
    if (request.url.path == '/auth/v1/token' &&
        request.url.queryParameters['grant_type'] == 'refresh_token') {
      final session = await vault.freshSession(inner, origin, anonKey);
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(session))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.url.path == '/auth/v1/logout' &&
        request.url.queryParameters['scope'] != 'others') {
      await vault.removePersistedSession();
    }
    final expectedEpoch = await vault.currentEpoch();
    final response = await _send(inner, request);
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        {
          '/auth/v1/token',
          '/auth/v1/verify',
          '/auth/v1/signup',
        }.contains(request.url.path)) {
      final data = _decodeObject(response.body);
      if (data['access_token'] != null) {
        await vault.acceptLogin(
          data,
          expectedEpoch: expectedEpoch,
          guarded: true,
        );
      }
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close() => inner.close();
}

/// Non-native PKCE state is process-local; never persisted as plaintext.
class EphemeralPkceStorage extends GotrueAsyncStorage {
  final Map<String, String> _values = {};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

class SecurePkceStorage extends GotrueAsyncStorage {
  SecurePkceStorage(this.secrets);
  final AuthSecrets secrets;
  @override
  Future<String?> getItem({required String key}) => secrets.read('pkce_$key');
  @override
  Future<void> setItem({required String key, required String value}) =>
      secrets.write('pkce_$key', value);
  @override
  Future<void> removeItem({required String key}) => secrets.delete('pkce_$key');
}
