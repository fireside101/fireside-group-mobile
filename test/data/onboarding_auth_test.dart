import 'dart:async';
import 'dart:convert';

import 'package:fireside_group/data/services/auth_service.dart';
import 'package:fireside_group/data/services/secure_update_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InterceptSdk extends http.BaseClient {
  InterceptSdk(this.inner, this.afterRefresh);
  final http.Client inner;
  final Future<void> Function() afterRefresh;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (request.url.path == '/auth/v1/token') await afterRefresh();
    return response;
  }
}

class Secrets implements AuthSecrets {
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

class Gate implements AuthGate {
  @override
  Future<T> run<T>(Future<T> Function() action) => action();
}

void main() {
  const email = 'eligible@example.test';
  late AuthService service;
  late SupabaseClient sdk;
  late SecureSessionVault vault;
  late Secrets secrets;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  late Future<void> Function() afterSdkRefresh;
  setUp(() {
    afterSdkRefresh = () async {};
    secrets = Secrets();
    vault = SecureSessionVault(secrets: secrets, gate: Gate());
    requests = [];
    respond = (_) async => http.Response('{"next":"login"}', 200);
    final transport = MockClient((request) {
      requests.add(request);
      return respond(request);
    });
    sdk = SupabaseClient(
      'https://supabase.firesideafrica.cloud',
      'public-test-key',
      httpClient: InterceptSdk(
        CoordinatedAuthClient(
          transport,
          vault,
          Uri.parse('https://supabase.firesideafrica.cloud'),
          'public-test-key',
        ),
        () => afterSdkRefresh(),
      ),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    service = AuthService(client: sdk, transport: transport, vault: vault);
  });
  tearDown(() async {
    await sdk.dispose();
  });
  test(
    'eligible existing and new discovery uses only pinned server, no Origin',
    () async {
      expect(await service.discover(email), 'login');
      respond = (_) async => http.Response('{"next":"register"}', 200);
      expect(await service.discover(email), 'register');
      expect(
        requests.every(
          (r) => r.url.toString() == 'https://firesidegroup.firesideafrica.cloud/api/auth/onboarding/discover',
        ),
        isTrue,
      );
      expect(requests.first.headers.containsKey('Origin'), isFalse);
      expect(jsonDecode(requests.first.body), {'email': email});
      expect(secrets.values, isEmpty);
    },
  );
  test(
    'new registration confirms exactly and never creates a session',
    () async {
      respond = (_) async => http.Response(
        '{"next":"login","message":"Account created. Sign in with your new password."}',
        200,
      );
      expect(
        await service.register(
          email: email,
          password: 'test-password',
          confirmPassword: 'test-password',
        ),
        isNull,
      );
      expect(requests.single.url.path, endsWith('/register'));
      expect(jsonDecode(requests.single.body), {
        'email': email,
        'password': 'test-password',
        'confirmPassword': 'test-password',
      });
      expect(sdk.auth.currentSession, isNull);
      expect(secrets.values, isEmpty);
    },
  );
  test('mismatch and invalid password never reach server', () async {
    for (final password in ['short', 'x' * 1025, 'test-password']) {
      await expectLater(
        service.register(
          email: email,
          password: password,
          confirmPassword: 'different',
        ),
        throwsA(isA<OnboardingException>()),
      );
    }
    expect(requests, isEmpty);
  });
  for (final status in [400, 401, 403, 409, 429, 503]) {
    test('server error $status fails closed without generic signup/reset', () async {
      const message =
          'Your email is not in PI. Kindly contact HR or the Business Intelligence and Digital Engineering team for assistance.';
      respond = (_) async => http.Response(
        jsonEncode({'error': message}),
        status,
        headers: {'retry-after': '900'},
      );
      await expectLater(
        service.discover(email),
        throwsA(
          isA<OnboardingException>()
              .having((e) => e.statusCode, 'status', status)
              .having(
                (e) => e.message,
                'message',
                status == 429
                    ? 'Too many attempts. Please wait before trying again.'
                    : message,
              )
              .having(
                (e) => e.retryAfterSeconds,
                'retry',
                status == 429 || status == 503 ? 900 : null,
              ),
        ),
      );
      expect(requests, hasLength(1));
      expect(secrets.values, isEmpty);
    });
  }
  test('uncertain create is not automatically retried or reset', () async {
    respond = (_) async =>
        http.Response('{"error":"Please try discovery again."}', 503);
    await expectLater(
      service.register(
        email: email,
        password: 'test-password',
        confirmPassword: 'test-password',
      ),
      throwsA(isA<OnboardingException>()),
    );
    expect(requests, hasLength(1));
  });
  test('malformed success and redirects never authorize', () async {
    for (final response in [
      http.Response('{"next":"unknown"}', 200),
      http.Response('not json', 200),
      http.Response('', 302),
    ]) {
      respond = (_) async => response;
      await expectLater(
        service.discover(email),
        throwsA(isA<OnboardingException>()),
      );
    }
    expect(requests.every((r) => !r.followRedirects), isTrue);
  });
  Map<String, dynamic> session(String userEmail) => {
    'access_token': 'test-access',
    'refresh_token': 'test-refresh',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': {
      'id': 'user-one',
      'aud': 'authenticated',
      'email': userEmail,
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {},
    },
  };
  test('portal login refresh is committed encrypted before SDK session and rotates epoch', () async {
    respond = (r) async => r.url.path.endsWith('/login')
        ? http.Response(
            '{"session":{"access_token":"portal-access","refresh_token":"portal-refresh"}}',
            200,
          )
        : http.Response(jsonEncode(session(email)), 200);
    final user = await service.signIn(email: email, password: 'test-password');
    expect(user?.email, email);
    expect(sdk.auth.currentSession?.refreshToken, 'test-refresh');
    expect(vault.binding, isNotNull);
    expect(
      jsonDecode(secrets.values.values.single)['session']['refresh_token'],
      'test-refresh',
    );
    expect(requests.where((r) => r.url.path == '/auth/v1/token'), hasLength(1));
  });
  test('logout during delayed login cannot resurrect old account', () async {
    final pending = Completer<http.Response>();
    respond = (_) => pending.future;
    final login = service.signIn(email: email, password: 'test-password');
    await Future<void>.delayed(Duration.zero);
    await service.signOut();
    pending.complete(
      http.Response(
        '{"session":{"access_token":"old","refresh_token":"old"}}',
        200,
      ),
    );
    await expectLater(login, throwsA(isA<StateError>()));
    expect(sdk.auth.currentSession, isNull);
    expect(await vault.hasAccessToken(), isFalse);
  });
  test('logout during SDK hydration cannot resurrect SDK identity', () async {
    final release = Completer<void>();
    final started = Completer<void>();
    afterSdkRefresh = () async {
      started.complete();
      await release.future;
    };
    respond = (r) async => r.url.path.endsWith('/login')
        ? http.Response(
            '{"session":{"access_token":"portal-access","refresh_token":"portal-refresh"}}',
            200,
          )
        : http.Response(jsonEncode(session(email)), 200);
    final login = service.signIn(email: email, password: 'test-password');
    final failedLogin = expectLater(login, throwsA(isA<StateError>()));
    await started.future;
    final logout = service.signOut();
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await failedLogin;
    await logout;
    expect(sdk.auth.currentSession, isNull);
    expect(await vault.hasAccessToken(), isFalse);
  });
  test('logout during refresh exchange cannot commit tokens', () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    respond = (r) async {
      if (r.url.path.endsWith('/login')) {
        return http.Response(
          '{"session":{"access_token":"portal-access","refresh_token":"portal-refresh"}}',
          200,
        );
      }
      started.complete();
      return pending.future;
    };
    final login = service.signIn(email: email, password: 'test-password');
    await started.future;
    await service.signOut();
    pending.complete(http.Response(jsonEncode(session(email)), 200));
    await expectLater(login, throwsA(isA<StateError>()));
    expect(await vault.hasAccessToken(), isFalse);
    expect(sdk.auth.currentSession, isNull);
  });
  test(
    'switch accounts while old login is pending preserves winning identity',
    () async {
      final old = Completer<http.Response>();
      final started = Completer<void>();
      respond = (r) async {
        if (r.url.path.endsWith('/login')) {
          final body = jsonDecode(r.body) as Map;
          if (body['email'] == email) {
            started.complete();
            return old.future;
          }
          return http.Response(
            '{"session":{"access_token":"new-access","refresh_token":"new-refresh"}}',
            200,
          );
        }
        return http.Response(jsonEncode(session('other@example.test')), 200);
      };
      final previous = service.signIn(email: email, password: 'test-password');
      await started.future;
      final current = await service.signIn(
        email: 'other@example.test',
        password: 'test-password',
      );
      old.complete(
        http.Response(
          '{"session":{"access_token":"old-access","refresh_token":"old-refresh"}}',
          200,
        ),
      );
      await expectLater(previous, throwsA(isA<StateError>()));
      expect(current?.email, 'other@example.test');
      expect(sdk.auth.currentUser?.email, 'other@example.test');
      expect(
        jsonDecode(secrets.values.values.single)['session']['user']['email'],
        'other@example.test',
      );
    },
  );
  test(
    'server refresh identity mismatch cannot enter secure storage',
    () async {
      respond = (r) async => r.url.path.endsWith('/login')
          ? http.Response(
              '{"session":{"access_token":"portal-access","refresh_token":"portal-refresh"}}',
              200,
            )
          : http.Response(jsonEncode(session('other@example.test')), 200);
      await expectLater(
        service.signIn(email: email, password: 'test-password'),
        throwsA(isA<StateError>()),
      );
      expect(secrets.values, isEmpty);
      expect(sdk.auth.currentSession, isNull);
    },
  );
}
