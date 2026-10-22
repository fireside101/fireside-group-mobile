import 'package:fireside_group/app.dart';
import 'package:fireside_group/data/services/auth_service.dart';
import 'package:fireside_group/features/auth/auth_controller.dart';
import 'package:fireside_group/features/home/widgets/search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';

/// Simulates a signed-in Workspace user so the auth gate passes without
/// hitting Google's platform flow.
class _FakeAuthService extends AuthService {
  @override
  Future<AuthSession?> restoreSession() async =>
      const AuthSession(name: 'Test User', email: 'test@fireside.africa');

  @override
  Future<AuthSession?> signIn({
    required String email,
    required String password,
  }) async =>
      const AuthSession(name: 'Test User', email: 'test@fireside.africa');

  @override
  Future<void> signOut() async {}
}

Future<void> _settle(WidgetTester tester) async {
  // The FuturisticNavBar runs continuous animations, so pumpAndSettle would
  // never finish. Pump a fixed window instead to let transitions complete.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('sign-in -> home -> search -> open -> recent strip', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(_FakeAuthService())],
        child: const FiresideGroupApp(),
      ),
    );
    await _settle(tester);

    // Home renders the hero search and the launcher.
    expect(find.textContaining('Welcome back'), findsOneWidget);
    expect(find.byType(AppSearchBar), findsOneWidget);
    expect(find.text('Fireside BI Reporting'), findsOneWidget);

    // Search filters the launcher down to the matching card.
    await tester.enterText(find.byType(TextField).first, 'warehouse');
    await _settle(tester);
    expect(find.text('Warehouse'), findsOneWidget);
    expect(find.text('Fireside BI Reporting'), findsNothing);

    // Clear the search so the BI card is visible again.
    await tester.enterText(find.byType(TextField).first, '');
    await _settle(tester);

    // Open the no-URL app's detail screen and confirm the Internal service state.
    await tester.tap(find.text('Fireside BI Reporting'));
    await _settle(tester);
    expect(find.text('About this app'), findsOneWidget);
    expect(find.text('Internal service'), findsNWidgets(2));

    // Go back and confirm the recent strip now lists the app.
    await tester.tap(find.byType(BackButton));
    await _settle(tester);
    expect(find.text('Recent'), findsOneWidget);
  });
}
