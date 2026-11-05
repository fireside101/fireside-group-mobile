import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/app_detail/app_detail_screen.dart';
import '../../../features/app_viewer/app_webview_screen.dart';
import '../../../features/applications/all_applications_screen.dart';
import '../../../features/admin_logs/admin_logs_screen.dart';
import '../../../features/auth/auth_controller.dart';
import '../../../features/auth/account_setup_screen.dart';
import '../../../features/auth/sign_in_screen.dart';
import '../../../features/home/home_screen.dart';
import '../../../features/profile/profile_screen.dart';
import '../../../features/settings/settings_screen.dart';
import '../../../features/support/support_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final authenticated =
          auth.hasValue && !auth.isLoading && auth.value != null;
      final atAuthEntry =
          state.matchedLocation == '/sign-in' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/reset-password' ||
          state.matchedLocation == '/account-setup';

      if (!authenticated && !atAuthEntry) return '/sign-in';
      if (authenticated && atAuthEntry) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(path: '/register', redirect: (context, state) => '/sign-in'),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) =>
            const AccountSetupScreen(mode: AccountSetupMode.resetPassword),
      ),
      GoRoute(
        path: '/account-setup',
        redirect: (context, state) => '/register',
      ),
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/applications',
        builder: (context, state) => const AllApplicationsScreen(),
      ),
      GoRoute(
        path: '/support',
        builder: (context, state) => const SupportScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/admin-logs',
        builder: (context, state) => const AdminLogsScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/app/:appId',
        builder: (context, state) =>
            AppDetailScreen(appId: state.pathParameters['appId']!),
      ),
      GoRoute(
        path: '/app/:appId/open',
        builder: (context, state) => AppWebViewScreen(
          key: ValueKey(state.pathParameters['appId']),
          appId: state.pathParameters['appId']!,
        ),
      ),
    ],
  );
  ref.listen(authControllerProvider, (_, _) => router.refresh());
  return router;
});
