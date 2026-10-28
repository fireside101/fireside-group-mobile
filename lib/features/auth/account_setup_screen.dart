import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../shell/app_header.dart';
import 'auth_controller.dart';

enum AccountSetupMode { register, resetPassword }

/// Native mobile UI for account registration and password reset.
class AccountSetupScreen extends ConsumerStatefulWidget {
  const AccountSetupScreen({super.key, required this.mode});

  final AccountSetupMode mode;

  @override
  ConsumerState<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends ConsumerState<AccountSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _message;
  bool _messageIsError = true;
  bool _busy = false;

  bool get _isRegister => widget.mode == AccountSetupMode.register;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
                  vertical: 40,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _AccountSetupCard(
                    formKey: _formKey,
                    emailController: _emailController,
                    passwordController: _passwordController,
                    confirmPasswordController: _confirmPasswordController,
                    isRegister: _isRegister,
                    busy: _busy,
                    message: _message,
                    messageIsError: _messageIsError,
                    onSubmit: _submit,
                    onBack: () => context.go('/sign-in'),
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
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      if (_isRegister) {
        final registered = await ref
            .read(authControllerProvider.notifier)
            .register(_emailController.text, _passwordController.text);
        if (!mounted) return;
        setState(() {
          _busy = false;
          _message = registered
              ? 'Your account is ready. You can continue to the app.'
              : 'Account created. Check your email to confirm your account, then sign in.';
          _messageIsError = false;
        });
        return;
      }

      await ref
          .read(authControllerProvider.notifier)
          .sendPasswordReset(_emailController.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message =
            'If that account exists, a password reset email has been sent.';
        _messageIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = _friendlyError(error);
        _messageIsError = true;
      });
    }
  }

  String _friendlyError(Object error) {
    if (error is StateError) return error.message;
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('already registered') ||
          message.contains('already been registered')) {
        return 'That email is already registered. Try resetting the password.';
      }
      if (message.contains('invalid email')) {
        return 'Enter a valid work email address.';
      }
      return error.message;
    }
    return 'We could not complete that request. Please try again.';
  }
}

class _AccountSetupCard extends StatelessWidget {
  const _AccountSetupCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.isRegister,
    required this.busy,
    required this.message,
    required this.messageIsError,
    required this.onSubmit,
    required this.onBack,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool isRegister;
  final bool busy;
  final String? message;
  final bool messageIsError;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

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
              isRegister ? 'Create your account' : 'Reset your password',
              style: AppTypography.displayMedium().copyWith(
                color: colors.charcoal,
                fontSize: 30,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isRegister
                  ? 'Use your Fireside work email to create your account.'
                  : 'Enter your Fireside work email and we will send you a secure reset link.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.muted, height: 1.45),
            ),
            if (message != null) ...[
              const SizedBox(height: 18),
              _SetupMessage(text: message!, isError: messageIsError),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: emailController,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: isRegister
                  ? TextInputAction.next
                  : TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter your email.';
                }
                if (!value.contains('@')) return 'Enter a valid email.';
                return null;
              },
            ),
            if (isRegister) ...[
              const SizedBox(height: 15),
              TextFormField(
                controller: passwordController,
                enabled: !busy,
                obscureText: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter a password.';
                  }
                  if (value.length < 8) return 'Use at least 8 characters.';
                  return null;
                },
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: confirmPasswordController,
                enabled: !busy,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
                validator: (value) => value != passwordController.text
                    ? 'Passwords do not match.'
                    : null,
                onFieldSubmitted: (_) => onSubmit(),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onSubmit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    busy
                        ? (isRegister ? 'Creating account…' : 'Sending…')
                        : (isRegister ? 'Create account' : 'Send reset link'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: busy ? null : onBack,
                child: const Text('Back to sign in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupMessage extends StatelessWidget {
  const _SetupMessage({required this.text, required this.isError});

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
