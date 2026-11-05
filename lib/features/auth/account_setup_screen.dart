import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../shell/app_header.dart';
import 'auth_controller.dart';

enum AccountSetupMode { resetPassword }

/// Existing explicit password recovery is separate from PI-only onboarding.
/// Registration entry points redirect to the email-first screen instead.
class AccountSetupScreen extends ConsumerStatefulWidget {
  const AccountSetupScreen({super.key, required this.mode});
  final AccountSetupMode mode;
  @override
  ConsumerState<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends ConsumerState<AccountSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .sendPasswordReset(_email.text);
      if (!mounted) return;
      setState(
        () => _message =
            'If that account exists, a password reset email has been sent.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'We could not complete that request. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.appColors.ivory,
    body: Column(
      children: [
        const AppHeader(),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Reset your password',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Enter your Fireside work email and we will send you a secure reset link.',
                      ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(_message!),
                        ),
                      TextFormField(
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (v) => v == null || !v.contains('@')
                            ? 'Enter a valid email.'
                            : null,
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(_busy ? 'Sending…' : 'Send reset link'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => context.go('/sign-in'),
                        child: const Text('Back to sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
