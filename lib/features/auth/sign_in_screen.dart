import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'auth_controller.dart';

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: colors.ivory,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/images/logo-fireside.jpeg',
                          fit: BoxFit.cover,
                          width: 80,
                          height: 80,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Fireside Group',
                    textAlign: TextAlign.center,
                    style: AppTypography.displayMedium().copyWith(
                      color: colors.charcoal,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your internal applications, in one place. Sign in with your '
                    'Fireside Africa Google Workspace account to continue.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colors.muted, height: 1.4),
                  ),
                  const SizedBox(height: 40),
                  if (auth.hasError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Sign-in failed. Please try again.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colors.statusBad),
                      ),
                    ),
                  _GoogleSignInButton(
                    onPressed: auth.isLoading
                        ? null
                        : () => _signIn(context, ref),
                  ),
                  if (auth.isLoading) ...[
                    const SizedBox(height: 20),
                    const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    'Access is restricted to fireside.africa accounts.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    final success = await ref.read(authControllerProvider.notifier).signIn();
    if (!context.mounted) return;
    if (success) {
      context.go('/');
    }
  }
}

class _GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _GoogleSignInButton({this.onPressed});

  @override
  Widget build(BuildContext context) {
    // Follows Google's brand button spec: white surface, G logo, full width.
    return Material(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _GoogleLogo(),
              const SizedBox(width: 14),
              Text(
                'Sign in with Google',
                style: AppTypography.bodyLarge().copyWith(
                  color: const Color(0xFF1F1F1F),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    // Four-color Google "G", painted at runtime so no binary asset is needed.
    // Swap for the official google-logo.png if brand review requires it.
    return SizedBox(
      width: 22,
      height: 22,
      child: Text(
        'G',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 24,
          height: 0.9,
          fontWeight: FontWeight.w800,
          fontFamily: 'sans-serif',
          foreground: Paint()..shader = _googleShader,
        ),
      ),
    );
  }
}

final _googleShader = LinearGradient(
  colors: const [
    Color(0xFF4285F4),
    Color(0xFF34A853),
    Color(0xFFFBBC05),
    Color(0xFFEA4335),
  ],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
).createShader(const Rect.fromLTWH(0, 0, 22, 22));
