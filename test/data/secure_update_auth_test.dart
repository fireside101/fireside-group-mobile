import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fireside_group/data/services/secure_update_auth.dart';

String fixtureCredential() => base64UrlEncode(
  List<int>.generate(24, (_) => Random.secure().nextInt(256)),
);

class MemorySecrets implements AuthSecrets {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class MemoryGate implements AuthGate {
  Future<void> tail = Future.value();
  @override
  Future<T> run<T>(Future<T> Function() action) {
    final result = tail.then((_) => action());
    tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

Map<String, dynamic> session(String token, {String user = 'employee'}) => {
  'access_token': token,
  'refresh_token': 'refresh-$token',
  'expires_at': 1,
  'token_type': 'bearer',
  'user': {
    'id': user,
    'app_metadata': {},
    'user_metadata': {},
    'aud': 'authenticated',
    'created_at': '2026-01-01T00:00:00Z',
  },
};
void main() {
  test(
    'authenticated response bodies are capped before SDK delivery',
    () async {
      final vault = SecureSessionVault(
        secrets: MemorySecrets(),
        gate: MemoryGate(),
      );
      final client = CoordinatedAuthClient(
        MockClient((_) async => http.Response('x' * (1024 * 1024 + 1), 200)),
        vault,
        Uri.parse('https://example.test'),
        'anon',
      );
      // /user does not decode a session in the coordinator: this must be a
      // transport bound, not an incidental JSON parse failure on /token.
      await expectLater(
        client.get(Uri.parse('https://example.test/auth/v1/user')),
        throwsStateError,
      );
    },
  );

  test(
    'real SDK PKCE exchange enrolls only the authenticated token response',
    () async {
      final secrets = MemorySecrets();
      final vault = SecureSessionVault(secrets: secrets, gate: MemoryGate());
      final pkce = SecurePkceStorage(secrets);
      final client = SupabaseClient(
        'https://example.test',
        'anon',
        authOptions: AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: AuthFlowType.pkce,
          pkceAsyncStorage: pkce,
        ),
        httpClient: CoordinatedAuthClient(
          MockClient((request) async {
            expect(request.url.path, '/auth/v1/token');
            expect(request.url.queryParameters['grant_type'], 'pkce');
            final body = jsonDecode(request.body) as Map;
            expect(body['auth_code'], 'synthetic-auth-code');
            expect(body['code_verifier'], isNotEmpty);
            expect(await vault.accessToken(), isNull);
            return http.Response(
              jsonEncode({
                ...session('oauth'),
                'expires_at': 9999999999,
                'expires_in': 3600,
              }),
              200,
            );
          }),
          vault,
          Uri.parse('https://example.test'),
          'anon',
        ),
      );
      addTearDown(client.dispose);
      final redirect = await client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
      );
      expect(
        Uri.parse(redirect.url).queryParameters['code_challenge'],
        isNotEmpty,
      );
      expect(await vault.accessToken(), isNull);
      final result = await client.auth.exchangeCodeForSession(
        'synthetic-auth-code',
      );
      expect(result.session.accessToken, 'oauth');
      expect(jsonDecode((await vault.accessToken())!)['access_token'], 'oauth');
      expect(
        await pkce.getItem(key: 'supabase.auth.token-code-verifier'),
        isNull,
      );
    },
  );
  test(
    'real SDK signup and OTP verification enroll authenticated sessions',
    () async {
      for (final verify in [false, true]) {
        final vault = SecureSessionVault(
          secrets: MemorySecrets(),
          gate: MemoryGate(),
        );
        final client = SupabaseClient(
          'https://example.test',
          'anon',
          authOptions: AuthClientOptions(
            autoRefreshToken: false,
            pkceAsyncStorage: SecurePkceStorage(vault.secrets),
          ),
          httpClient: CoordinatedAuthClient(
            MockClient((request) async {
              expect(
                request.url.path,
                verify ? '/auth/v1/verify' : '/auth/v1/signup',
              );
              return http.Response(
                jsonEncode({
                  ...session('issued'),
                  'expires_at': 9999999999,
                  'expires_in': 3600,
                }),
                200,
              );
            }),
            vault,
            Uri.parse('https://example.test'),
            'anon',
          ),
        );
        try {
          if (verify) {
            await client.auth.verifyOTP(
              email: 'synthetic@example.test',
              token: '123456',
              type: OtpType.email,
            );
          } else {
            await client.auth.signUp(
              email: 'synthetic@example.test',
              password: fixtureCredential(),
            );
          }
          expect(client.auth.currentSession?.accessToken, 'issued');
          expect(
            jsonDecode((await vault.accessToken())!)['access_token'],
            'issued',
          );
        } finally {
          await client.dispose();
        }
      }
    },
  );

  test('unauthenticated signup response cannot enroll a session', () async {
    final vault = SecureSessionVault(
      secrets: MemorySecrets(),
      gate: MemoryGate(),
    );
    final client = SupabaseClient(
      'https://example.test',
      'anon',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: SecurePkceStorage(vault.secrets),
      ),
      httpClient: CoordinatedAuthClient(
        MockClient(
          (_) async =>
              http.Response(jsonEncode(session('unused')['user']), 200),
        ),
        vault,
        Uri.parse('https://example.test'),
        'anon',
      ),
    );
    addTearDown(client.dispose);
    final result = await client.auth.signUp(
      email: 'synthetic@example.test',
      password: fixtureCredential(),
    );
    expect(result.session, isNull);
    expect(await vault.accessToken(), isNull);
  });

  test('ephemeral PKCE storage is isolated and removable', () async {
    final first = EphemeralPkceStorage();
    final second = EphemeralPkceStorage();
    await first.setItem(key: 'verifier', value: 'synthetic-verifier');
    expect(await first.getItem(key: 'verifier'), 'synthetic-verifier');
    expect(await second.getItem(key: 'verifier'), isNull);
    await first.removeItem(key: 'verifier');
    expect(await first.getItem(key: 'verifier'), isNull);
  });
  test(
    'logout during rotation rejects late refresh and cannot re-enroll tokens',
    () async {
      final vault = SecureSessionVault(
        secrets: MemorySecrets(),
        gate: MemoryGate(),
      );
      await vault.acceptLogin(session('expired'));
      final entered = Completer<void>();
      final finish = Completer<void>();
      final rotating = vault.freshSession(
        MockClient((_) async {
          entered.complete();
          await finish.future;
          return http.Response(
            jsonEncode({...session('late'), 'expires_at': 9999999999}),
            200,
          );
        }),
        Uri.parse('https://example.test'),
        'anon',
      );
      final rejection = expectLater(rotating, throwsStateError);
      await entered.future;
      final logout = vault.removePersistedSession();
      finish.complete();
      await rejection;
      await logout;
      expect(await vault.accessToken(), isNull);
    },
  );
  test(
    'revoked refresh fails closed and leaves a durable signed-out tombstone',
    () async {
      final vault = SecureSessionVault(
        secrets: MemorySecrets(),
        gate: MemoryGate(),
      );
      await vault.acceptLogin(session('expired'));
      var requests = 0;
      await expectLater(
        vault.checkPrivate(
          MockClient((request) async {
            requests++;
            expect(request.url.path, '/auth/v1/token');
            return http.Response('{"error":"synthetic-revocation"}', 401);
          }),
          Uri.parse('https://example.test'),
          'anon',
        ),
        throwsStateError,
      );
      expect(requests, 1);
      expect(await vault.accessToken(), isNull);
    },
  );
  test(
    'malformed credential-bearing responses never escape through errors',
    () async {
      final vault = SecureSessionVault(
        secrets: MemorySecrets(),
        gate: MemoryGate(),
      );
      await vault.acceptLogin(session('expired'));
      try {
        await vault.freshSession(
          MockClient(
            (_) async => http.Response('secret-token-and-signed-url', 200),
          ),
          Uri.parse('https://example.test'),
          'anon',
        );
        fail('must reject malformed response');
      } catch (error) {
        expect(
          error.toString(),
          isNot(contains('secret-token-and-signed-url')),
        );
        expect(error, isA<StateError>());
      }
    },
  );
  test('real Supabase SDK login, refresh and private function use coordinated transport', () async {
    final secrets = MemorySecrets();
    final gate = MemoryGate();
    final vault = SecureSessionVault(secrets: secrets, gate: gate);
    final seen = <String>[];
    final inner = MockClient((request) async {
      seen.add(request.url.path);
      if (request.url.path == '/auth/v1/token') {
        return http.Response(
          jsonEncode({
            ...session('sdk'),
            'expires_at': 9999999999,
            'expires_in': 3600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      expect(request.url.path, '/functions/v1/mobile-update');
      expect(request.headers['authorization'], 'Bearer sdk');
      return http.Response(
        '{"release":null}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = SupabaseClient(
      'https://example.test',
      'synthetic-anon',
      httpClient: CoordinatedAuthClient(
        inner,
        vault,
        Uri.parse('https://example.test'),
        'synthetic-anon',
      ),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'synthetic@example.test',
      password: fixtureCredential(),
    );
    expect(jsonDecode((await vault.accessToken())!)['access_token'], 'sdk');
    await client.auth.refreshSession(); // Returns durable fresh session, no duplicate rotation.
    expect((await client.functions.invoke('mobile-update')).status, 200);
    expect(seen, ['/auth/v1/token', '/functions/v1/mobile-update']);
  });
  test('logout tombstone rejects delayed login response, even initially signed out', () async {
    final vault = SecureSessionVault(
      secrets: MemorySecrets(),
      gate: MemoryGate(),
    );
    final entered = Completer<void>();
    final finish = Completer<void>();
    final client = CoordinatedAuthClient(
      MockClient((_) async {
        entered.complete();
        await finish.future;
        return http.Response(jsonEncode(session('late')), 200);
      }),
      vault,
      Uri.parse('https://example.test'),
      'anon',
    );
    final login = client.post(
      Uri.parse('https://example.test/auth/v1/token?grant_type=password'),
    );
    final rejection = expectLater(login, throwsStateError);
    await entered.future;
    await vault.removePersistedSession();
    finish.complete();
    await rejection;
    expect(await vault.accessToken(), isNull);
  });
  test('two engines coordinate rotation and stale persistence cannot restore logout', () async {
    final secrets = MemorySecrets();
    final gate = MemoryGate();
    final foreground = SecureSessionVault(secrets: secrets, gate: gate);
    await foreground.acceptLogin(session('old'));
    final worker = SecureSessionVault(secrets: secrets, gate: gate);
    await worker.accessToken();
    var refreshes = 0;
    final transport = MockClient((request) async {
      refreshes++;
      expect(jsonDecode(request.body)['refresh_token'], 'refresh-old');
      return http.Response(
        jsonEncode({...session('new'), 'expires_at': 9999999999}),
        200,
      );
    });
    await worker.freshSession(
      transport,
      Uri.parse('https://example.test'),
      'anon',
    );
    await foreground.freshSession(
      transport,
      Uri.parse('https://example.test'),
      'anon',
    );
    expect(refreshes, 1);
    await foreground.removePersistedSession();
    await worker.persistSession(jsonEncode(session('new')));
    expect(await worker.accessToken(), isNull);
  });
  test(
    'private response is discarded if logout occurs during request',
    () async {
      final secrets = MemorySecrets();
      final gate = MemoryGate();
      final vault = SecureSessionVault(secrets: secrets, gate: gate);
      await vault.acceptLogin({...session('valid'), 'expires_at': 9999999999});
      final entered = Completer<void>();
      final finish = Completer<void>();
      final transport = MockClient((request) async {
        expect(request.url.path, '/functions/v1/mobile-update');
        expect(request.headers['authorization'], 'Bearer valid');
        expect(request.followRedirects, isFalse);
        entered.complete();
        await finish.future;
        return http.Response('{"release":null}', 200);
      });
      final check = vault.checkPrivate(
        transport,
        Uri.parse('https://example.test'),
        'anon',
      );
      final rejection = expectLater(check, throwsStateError);
      await entered.future;
      await vault.removePersistedSession();
      finish.complete();
      await rejection;
    },
  );
  test(
    'logout during private-check refresh never sends an eligibility request',
    () async {
      final vault = SecureSessionVault(
        secrets: MemorySecrets(),
        gate: MemoryGate(),
      );
      await vault.acceptLogin(session('expired'));
      final entered = Completer<void>();
      final finish = Completer<void>();
      final seen = <String>[];
      final check = vault.checkPrivate(
        MockClient((request) async {
          seen.add(request.url.path);
          entered.complete();
          await finish.future;
          return http.Response(
            jsonEncode({...session('late'), 'expires_at': 9999999999}),
            200,
          );
        }),
        Uri.parse('https://example.test'),
        'anon',
      );
      final rejection = expectLater(check, throwsStateError);
      await entered.future;
      final logout = vault.removePersistedSession();
      finish.complete();
      await rejection;
      await logout;
      expect(seen, ['/auth/v1/token']);
      expect(await vault.accessToken(), isNull);
    },
  );

  test('stale isolate cannot clear a replacement account', () async {
    final secrets = MemorySecrets();
    final gate = MemoryGate();
    final a = SecureSessionVault(secrets: secrets, gate: gate);
    await a.acceptLogin(session('a'));
    final b = SecureSessionVault(secrets: secrets, gate: gate);
    await b.acceptLogin(session('b', user: 'other'));
    await a.removePersistedSession();
    expect(jsonDecode((await b.accessToken())!)['access_token'], 'b');
  });
}
