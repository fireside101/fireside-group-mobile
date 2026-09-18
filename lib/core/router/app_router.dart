import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/app_detail/app_detail_screen.dart';
import '../../../features/app_viewer/app_webview_screen.dart';
import '../../../features/applications/all_applications_screen.dart';
import '../../../features/auth/auth_controller.dart';
import '../../../features/auth/sign_in_screen.dart';
import '../../../features/home/home_screen.dart';
import '../../../features/profile/profile_screen.dart';
import '../../../features/settings/settings_screen.dart';
import '../../../features/support/support_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final authenticated =
          auth.hasValue && !auth.isLoading && auth.value != null;
      final atSignIn = state.matchedLocation == '/sign-in';

      if (!authenticated && !atSignIn) return '/sign-in';
      if (authenticated && atSignIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
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
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/app/:appId',
        builder: (context, state) => AppDetailScreen(
          appId: state.pathParameters['appId']!,
        ),
      ),
      GoRoute(
        path: '/app/:appId/open',
        builder: (context, state) => AppWebViewScreen(
          appId: state.pathParameters['appId']!,
        ),
      ),
    ],
  );
});