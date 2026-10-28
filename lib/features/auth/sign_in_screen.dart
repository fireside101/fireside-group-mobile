import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../shell/app_header.dart';
import 'auth_controller.dart';

/// Supabase email/password sign-in matching the web portal's login card.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _message;
  bool _messageIsError = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final auth = ref.watch(authControllerProvider);
    final busy = auth.isLoading;

    return Scaffold(
      backgroundColor: colors.ivory,
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 56,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _LoginCard(
                    formKey: _formKey,
                    emailController: _emailController,
                    passwordController: _passwordController,
                    busy: busy,
                    message: _message,
                    messageIsError: _messageIsError,
                    onSubmit: _submit,
                    onRegister: _register,
                    onResetPassword: _resetPassword,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _message = null);

    bool success;
    Object? error;
    try {
      success = await ref
          .read(authControllerProvider.notifier)
          .signIn(_emailController.text, _passwordController.text);
    } catch (caught) {
      success = false;
      error = caught;
    }
    if (!mounted) return;
    if (success) {
      context.go('/');
      return;
    }

    setState(() {
      _message = _friendlyError(error);
      _messageIsError = true;
    });
  }

  Future<void> _resetPassword() async {
    if (!mounted) return;
    context.push('/reset-password');
  }

  Future<void> _register() async {
    if (!mounted) return;
    context.push('/register');
  }

  String _friendlyError(Object? error) {
    if (error is StateError) return error.message;
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login credentials')) {
        return 'Email or password is incorrect.';
      }
      if (message.contains('already registered') ||
          message.contains('already been registered')) {
        return 'That email is already registered. Try signing in or resetting the password.';
      }
      if (message.contains('email not confirmed')) {
        return 'Confirm your email address before signing in.';
      }
      return error.message;
    }
    final text = error?.toString() ?? '';
    if (text.contains('Invalid login credentials')) {
      return 'Email or password is incorrect.';
    }
    return text.isEmpty ? 'Sign-in failed. Please try again.' : text;
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.busy,
    required this.onSubmit,
    required this.onRegister,
    required this.onResetPassword,
    this.message,
    required this.messageIsError,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool busy;
  final String? message;
  final bool messageIsError;
  final VoidCallback onSubmit;
  final VoidCallback onRegister;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.charcoal.withValues(alpha: 0.1),
            blurRadius: 48,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FIRESIDE GROUP ACCOUNT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.textAccent,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to launch applications',
              style: AppTypography.displayMedium().copyWith(
                color: colors.charcoal,
                fontSize: 30,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Use your Fireside Group credentials. Unauthenticated apps launch only after signing in.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.muted, height: 1.45),
            ),
            if (message != null) ...[
              const SizedBox(height: 18),
              _MessageBanner(text: message!, isError: messageIsError),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: emailController,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter your email.';
                }
                if (!value.contains('@')) return 'Enter a valid email.';
                return null;
              },
            ),
            const SizedBox(height: 15),
            TextFormField(
              controller: passwordController,
              enabled: !busy,
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your password.'
                  : null,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: busy ? null : onRegister,
                  child: const Text('Register'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: busy ? null : onResetPassword,
                  child: const Text('Reset password'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onSubmit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(busy ? 'Signing in…' : 'Sign In'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = isError ? colors.statusBad : colors.statusGreen;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: color, height: 1.35),
      ),
    );
  }
}
