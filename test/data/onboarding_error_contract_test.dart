import 'dart:convert';
import 'dart:io';

import 'package:fireside_group/data/services/onboarding_errors.dart';

import 'package:fireside_group/data/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Source-derived fixtures: Group src/lib/auth-errors.ts, not live captures.
void main() {
  Future<void> fails(
    http.Response response,
    String message, {
    int? retry,
  }) async {
    final service = AuthService(transport: MockClient((_) async => response));
    await expectLater(
      service.discover('eligible@example.test'),
      throwsA(
        isA<OnboardingException>()
            .having((e) => e.message, 'safe message', message)
            .having((e) => e.statusCode, 'status', response.statusCode)
            .having((e) => e.retryAfterSeconds, 'retry', retry),
      ),
    );
  }

  final contract = jsonDecode(
    File('test/data/fixtures/onboarding_errors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  test('client allowlist exactly matches all 18 server code/message pairs', () {
    expect(contract.length, 18);
    expect(onboardingErrorMessages, {
      for (final entry in contract.entries) entry.key: entry.value['error'],
    });
  });
  for (final entry in contract.entries) {
    test(
      'server contract ${entry.key} decodes through HTTP boundary',
      () async {
        final status = entry.value['status'] as int;
        final message = entry.value['error'] as String;
        await fails(
          http.Response(
            jsonEncode({'code': entry.key, 'error': 'private'}),
            status,
          ),
          message,
          retry: status == 429 ? 900 : null,
        );
        await fails(
          http.Response(
            jsonEncode({'error': message}),
            status,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
          message,
          retry: status == 429 ? 900 : null,
        );
      },
    );
  }

  test('stable codes win over untrusted provider error text', () async {
    for (final entry in {
      'INVALID_CREDENTIALS': (
        401,
        'Incorrect email or password. Please try again.',
      ),
      'PASSWORD_MISMATCH': (
        400,
        'Passwords do not match. Re-enter your confirmation.',
      ),
      'ACCOUNT_UNVERIFIED': (
        401,
        'This existing account is not ready for sign-in. Contact HR or the Business Intelligence and Digital Engineering team for assistance.',
      ),
      'SERVICE_BUSY': (
        503,
        'Account service is busy. Please try again shortly.',
      ),
    }.entries) {
      await fails(
        http.Response(
          jsonEncode({
            'code': entry.key,
            'error': 'secret-provider-diagnostic',
          }),
          entry.value.$1,
        ),
        entry.value.$2,
      );
    }
  });
  test('unknown code and untrusted legacy text never reach UI', () async {
    await fails(
      http.Response(
        '{"code":"INTERNAL","error":"secret-provider-diagnostic"}',
        503,
      ),
      'Account service is unavailable. Please try again later.',
    );
    await fails(
      http.Response('{"error":"secret-provider-diagnostic"}', 401),
      'Account service is unavailable. Please try again later.',
    );
  });
  test('allowlisted legacy error-only contract remains usable', () async {
    await fails(
      http.Response(
        '{"error":"Invalid email or password, or email verification is still required."}',
        401,
      ),
      'Email or password is incorrect, or this account is not ready for sign-in. Contact support if your password is correct.',
    );
    await fails(
      http.Response(
        '{"error":"Incorrect email or password. Please try again."}',
        401,
      ),
      'Incorrect email or password. Please try again.',
    );
  });
  test('429 retry-after survives invalid JSON and is bounded', () async {
    await fails(
      http.Response(
        '<html>proxy error</html>',
        429,
        headers: {'retry-after': '12'},
      ),
      'Too many attempts. Please wait before trying again.',
      retry: 12,
    );
    for (final retry in ['-1', '999999999999999999999', 'tomorrow']) {
      await fails(
        http.Response('{}', 429, headers: {'retry-after': retry}),
        'Too many attempts. Please wait before trying again.',
        retry: 900,
      );
    }
  });
  test(
    'provider busy preserves retry-after but never arbitrary text',
    () async {
      await fails(
        http.Response(
          '{"code":"SERVICE_BUSY","error":"private"}',
          503,
          headers: {'retry-after': '5'},
        ),
        'Account service is busy. Please try again shortly.',
        retry: 5,
      );
    },
  );
  test(
    'transport failures are connection errors not incorrect passwords',
    () async {
      var requests = 0;
      final service = AuthService(
        transport: MockClient((_) async {
          requests++;
          throw http.ClientException('secret connection details');
        }),
      );
      await expectLater(
        service.discover('eligible@example.test'),
        throwsA(
          isA<OnboardingException>().having(
            (e) => e.message,
            'message',
            'Unable to connect. Check your connection and try again.',
          ),
        ),
      );
      expect(requests, 1);
    },
  );
  test(
    'local confirmation mismatch is distinct from password length',
    () async {
      final service = AuthService(
        transport: MockClient(
          (_) async => throw StateError('No request allowed'),
        ),
      );
      await expectLater(
        service.register(
          email: 'eligible@example.test',
          password: 'synthetic',
          confirmPassword: 'mismatch',
        ),
        throwsA(
          isA<OnboardingException>().having(
            (e) => e.message,
            'message',
            'Passwords do not match. Re-enter your confirmation.',
          ),
        ),
      );
    },
  );
}
