import 'package:fireside_group/app.dart';
import 'package:fireside_group/data/services/auth_service.dart';
import 'package:fireside_group/features/auth/auth_controller.dart';
import 'package:fireside_group/features/home/widgets/search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Simulates a signed-in Workspace user so the auth gate passes without
/// hitting Google's platform flow.
class _FakeAuthService extends AuthService {
  @override
  Future<AuthSession?> restoreSession() async => const AuthSession(
        name: 'Test User',
        email: 'test@fireside.africa',
      );

  @override
  Future<bool> isSignedIn() async => true;

  @override
  Future<AuthSession?> signIn() async => const AuthSession(
        name: 'Test User',
        email: 'test@fireside.africa',
      );

  @override
  Future<void> signOut() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('sign-in -> home -> search -> open -> recent strip', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_FakeAuthService()),
        ],
        child: const FiresideGroupApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Home renders the hero search and the launcher.
    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.byType(AppSearchBar), findsOneWidget);
    expect(find.text('Fireside BI Reporting'), findsOneWidget);

    // Search filters the launcher down to the matching card.
    await tester.enterText(find.byType(TextField).first, 'warehouse');
    await tester.pumpAndSettle();
    expect(find.text('Warehouse'), findsOneWidget);
    expect(find.text('Fireside BI Reporting'), findsNothing);

    // Clear the search so the BI card is visible again.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();

    // Open the no-URL app and confirm the Internal service state.
    await tester.tap(find.text('Fireside BI Reporting'));
    await tester.pumpAndSettle();
    expect(find.text('Internal service'), findsOneWidget);

    // Close and confirm the recent strip now lists the app.
    await tester.tap(find.byIcon(LucideIcons.x).first);
    await tester.pumpAndSettle();
    expect(find.text('Recent'), findsOneWidget);
  });
}