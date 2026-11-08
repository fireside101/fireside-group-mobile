import 'package:fireside_group/core/theme/app_theme.dart';
import 'package:fireside_group/data/services/auth_service.dart';
import 'package:fireside_group/features/auth/auth_controller.dart';
import 'package:fireside_group/features/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class RecoveryPortal extends AuthService {
  int recoveries = 0;
  Object? error;
  String? lastEmail;
  @override
  Future<AuthSession?> restoreSession() async => null;
  @override
  Future<String> discover(String email) async => 'login';
  @override
  Future<String> requestPasswordRecovery(String email) async {
    recoveries++;
    lastEmail = email;
    if (error != null) throw error!;
    return 'If that email can sign in, a reset link has been sent.';
  }
}

void main() {
  late RecoveryPortal portal;

  Future<void> toPasswordStep(WidgetTester tester) async {
    portal = RecoveryPortal();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(portal)],
        child: MaterialApp(theme: buildTealTheme(), home: const SignInScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('forgot-password')), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, 'a@example.test');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  testWidgets('forgot password sends, explains the browser step, cools down', (
    tester,
  ) async {
    await toPasswordStep(tester);
    final forgot = find.byKey(const Key('forgot-password'));
    expect(find.text('Forgot password?'), findsOneWidget);
    await tester.ensureVisible(forgot);
    await tester.tap(forgot);
    await tester.pump();
    expect(portal.recoveries, 1);
    expect(portal.lastEmail, 'a@example.test');
    expect(
      find.text('If that email can sign in, a reset link has been sent.'),
      findsOneWidget,
    );
    expect(find.text(SignInScreenRecoveryCopy.help), findsOneWidget);
    expect(find.text('Resend link in 60s'), findsOneWidget);

    await tester.tap(forgot);
    await tester.pump();
    expect(portal.recoveries, 1, reason: 'cooldown blocks resend');

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Resend link in 30s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Resend reset link'), findsOneWidget);
    await tester.tap(forgot);
    await tester.pump();
    expect(portal.recoveries, 2);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('rate limit shows the error and honours Retry-After', (
    tester,
  ) async {
    await toPasswordStep(tester);
    portal.error = const OnboardingException(
      'Too many attempts.',
      statusCode: 429,
      retryAfterSeconds: 90,
    );
    final forgot = find.byKey(const Key('forgot-password'));
    await tester.ensureVisible(forgot);
    await tester.tap(forgot);
    await tester.pump();
    expect(find.text('Too many attempts.'), findsOneWidget);
    expect(find.text(SignInScreenRecoveryCopy.help), findsNothing);
    expect(find.text('Resend link in 90s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 91));
  });
}
