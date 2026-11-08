import 'dart:convert';

import 'package:fireside_group/core/mobile_targets.dart';
import 'package:fireside_group/data/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  late AuthService service;

  setUp(() {
    requests = [];
    respond = (_) => http.Response(
      jsonEncode({'message': 'Check your inbox for a reset link.'}),
      202,
    );
    service = AuthService(
      transport: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );
  });

  test('posts only the email to the portal recover endpoint', () async {
    final message = await service.requestPasswordRecovery('  a@example.test ');
    expect(message, 'Check your inbox for a reset link.');
    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.method, 'POST');
    expect(
      request.url.toString(),
      '${MobileTargets.fromEnvironment().portalOrigin}/api/auth/onboarding/recover',
    );
    expect(jsonDecode(request.body), {'email': 'a@example.test'});
    expect(request.headers['Content-Type'], startsWith('application/json'));
    // Mirrors discover/login: native clients send no Origin header, which the
    // portal accepts; a wrong Origin would be rejected with 403.
    expect(request.headers.containsKey('Origin'), isFalse);
  });

  test('blank 202 message falls back to the generic notice', () async {
    respond = (_) => http.Response('{}', 202);
    expect(
      await service.requestPasswordRecovery('a@example.test'),
      AuthService.recoveryFallbackMessage,
    );
  });

  test('rate limit surfaces Retry-After', () async {
    respond = (_) => http.Response(
      '{"code":"RATE_LIMITED"}',
      429,
      headers: {'retry-after': '120'},
    );
    await expectLater(
      service.requestPasswordRecovery('a@example.test'),
      throwsA(
        isA<OnboardingException>()
            .having((e) => e.statusCode, 'status', 429)
            .having((e) => e.retryAfterSeconds, 'retry', 120),
      ),
    );
  });

  test('redirects and unexpected statuses never count as sent', () async {
    for (final status in [200, 302, 503]) {
      respond = (_) => http.Response('{"message":"x"}', status);
      await expectLater(
        service.requestPasswordRecovery('a@example.test'),
        throwsA(isA<OnboardingException>()),
      );
    }
  });
}
