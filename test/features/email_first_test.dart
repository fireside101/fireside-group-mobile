import 'dart:async';

import 'package:fireside_group/core/theme/app_theme.dart';
import 'package:fireside_group/data/services/auth_service.dart';
import 'package:fireside_group/features/auth/auth_controller.dart';
import 'package:fireside_group/features/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Portal extends AuthService {
  String next = 'register';
  Object? error;
  int discovers = 0, registrations = 0, logins = 0;
  Completer<String>? pending;
  @override
  Future<AuthSession?> restoreSession() async => null;
  @override
  Future<String> discover(String email) async {
    discovers++;
    if (error != null) throw error!;
    return pending?.future ?? next;
  }

  @override
  Future<AuthSession?> register({
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    registrations++;
    if (error != null) throw error!;
    return null;
  }

  @override
  Future<AuthSession?> signIn({
    required String email,
    required String password,
  }) async {
    logins++;
    throw const OnboardingException(
      'Email or password is incorrect.',
      statusCode: 401,
    );
  }
}

void main() {
  late Portal portal;
  Future<void> render(WidgetTester tester) async {
    portal = Portal();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(portal)],
        child: MaterialApp(theme: buildTealTheme(), home: const SignInScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> discover(WidgetTester tester) async {
    await tester.enterText(
      find.byType(TextFormField).first,
      'eligible@example.test',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'email first has no password, generic signup or mail verification',
    (tester) async {
      await render(tester);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Register'), findsNothing);
      expect(find.textContaining('OTP'), findsNothing);
    },
  );
  testWidgets(
    'eligible new automatically gets two passwords, mismatch stays local, then login',
    (tester) async {
      await render(tester);
      await discover(tester);
      expect(find.byType(TextFormField), findsNWidgets(3));
      await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
      await tester.enterText(find.byType(TextFormField).at(2), 'mismatch');
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(portal.registrations, 0);
      await tester.enterText(find.byType(TextFormField).at(2), 'test-password');
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(portal.registrations, 1);
      expect(portal.logins, 0);
      expect(
        find.text('Account created. Sign in with your new password.'),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Sign In'), findsOneWidget);
    },
  );
  testWidgets(
    'existing identity only gets existing password; change email clears it',
    (tester) async {
      await render(tester);
      portal.next = 'login';
      await discover(tester);
      expect(find.byType(TextFormField), findsNWidgets(2));
      await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
      await tester.ensureVisible(find.text('Sign In'));
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      expect(portal.logins, 1);
      expect(portal.registrations, 0);
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      await tester.tap(find.text('Change email'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsOneWidget);
    },
  );
  testWidgets(
    'PI absence preserves exact assistance message and never exposes password',
    (tester) async {
      await render(tester);
      const message =
          'Your email is not in PI. Kindly contact HR or the Business Intelligence and Digital Engineering team for assistance.';
      portal.error = const OnboardingException(message, statusCode: 403);
      await discover(tester);
      expect(find.text(message), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(portal.registrations, 0);
    },
  );
  for (final status in [409, 503]) {
    testWidgets(
      '$status race/uncertain create returns to discovery without automatic replay',
      (tester) async {
        await render(tester);
        await discover(tester);
        portal.error = OnboardingException(
          'Rediscover before retrying.',
          statusCode: status,
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'test-password',
        );
        await tester.enterText(
          find.byType(TextFormField).at(2),
          'test-password',
        );
        await tester.ensureVisible(find.text('Create account'));
        await tester.tap(find.text('Create account'));
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsOneWidget);
        expect(portal.discovers, 1);
        expect(portal.registrations, 1);
        expect(portal.logins, 0);
      },
    );
  }
  testWidgets('429 honours retry-after without another server request', (
    tester,
  ) async {
    await render(tester);
    portal.error = const OnboardingException(
      'Too many attempts.',
      statusCode: 429,
      retryAfterSeconds: 900,
    );
    await discover(tester);
    expect(
      find.text('Too many attempts. Try again in 900 seconds.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(portal.discovers, 1);
  });
  testWidgets('pending discovery prevents double submit and email mutation', (
    tester,
  ) async {
    await render(tester);
    portal.pending = Completer<String>();
    await tester.enterText(
      find.byType(TextFormField).first,
      'eligible@example.test',
    );
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isFalse,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    portal.pending!.complete('login');
    await tester.pumpAndSettle();
    expect(portal.discovers, 1);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}
