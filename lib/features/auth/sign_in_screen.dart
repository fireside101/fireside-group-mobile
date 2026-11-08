import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/auth_service.dart';
import '../shell/app_header.dart';
import 'auth_controller.dart';

/// PI eligibility is decided exclusively by the portal. No native PI queries,
/// generic signup, confirmation mail or OTP. Password recovery is explicit
/// ("Forgot password?") and handled by the portal, which emails a link.
/// User-facing recovery copy, shared with tests.
abstract final class SignInScreenRecoveryCopy {
  static const help =
      'The link opens in your browser. Set a new password there, then come '
      'back and sign in here with your new password.';
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _next;
  String? _message;
  bool _busy = false;
  bool _error = true;
  DateTime? _retryAt;
  bool get _register => _next == 'register';

  static const recoveryCooldown = Duration(seconds: 60);
  String? _recoveryMessage;
  bool _recoveryError = false;
  bool _recovering = false;
  int _recoverySecondsLeft = 0;
  Timer? _recoveryTicker;

  // Tick-based (not wall clock) so the countdown is deterministic in tests.
  void _startRecoveryCooldown(Duration duration) {
    _recoverySecondsLeft = duration.inSeconds;
    _recoveryTicker?.cancel();
    _recoveryTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _recoverySecondsLeft--);
      if (_recoverySecondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _forgotPassword() async {
    if (_busy || _recovering || _recoverySecondsLeft > 0) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _recovering = true;
      _recoveryMessage = null;
    });
    try {
      final message = await ref
          .read(authServiceProvider)
          .requestPasswordRecovery(_email.text);
      if (!mounted) return;
      setState(() {
        _recoveryMessage = message;
        _recoveryError = false;
        _startRecoveryCooldown(recoveryCooldown);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recoveryError = true;
        _recoveryMessage = error is OnboardingException
            ? error.message
            : 'Password reset is unavailable. Please try again.';
        final retry = error is OnboardingException
            ? error.retryAfterSeconds
            : null;
        if (retry != null) {
          _startRecoveryCooldown(Duration(seconds: retry.clamp(1, 86400)));
        }
      });
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  @override
  void dispose() {
    _recoveryTicker?.cancel();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _changeEmail() {
    if (_busy) return;
    setState(() {
      _next = null;
      _message = null;
      _recoveryMessage = null;
      _password.clear();
      _confirm.clear();
    });
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final retryAt = _retryAt;
    if (retryAt != null && DateTime.now().isBefore(retryAt)) {
      setState(() {
        _message = 'Too many attempts. Please wait before trying again.';
        _error = true;
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _message = null;
      _error = true;
    });
    try {
      if (_next == null) {
        final next = await ref.read(authServiceProvider).discover(_email.text);
        if (!mounted) return;
        setState(() => _next = next);
      } else if (_register) {
        await ref
            .read(authControllerProvider.notifier)
            .register(_email.text, _password.text, _confirm.text);
        if (!mounted) return;
        setState(() {
          _next = 'login';
          _password.clear();
          _confirm.clear();
          _message = 'Account created. Sign in with your new password.';
          _error = false;
        });
      } else {
        final success = await ref
            .read(authControllerProvider.notifier)
            .signIn(_email.text, _password.text);
        if (!mounted) return;
        if (success) {
          context.go('/');
          return;
        }
        setState(() => _message = 'Sign-in failed. Please try again.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error is OnboardingException
            ? error.message
            : 'Sign-in unavailable. Please try again.';
        if (error is OnboardingException) {
          if (error.retryAfterSeconds != null) {
            _retryAt = DateTime.now().add(
              Duration(seconds: error.retryAfterSeconds!.clamp(1, 86400)),
            );
            final seconds = error.retryAfterSeconds!.clamp(1, 86400);
            _message = '${error.message} Try again in $seconds seconds.';
          }
          if (error.statusCode == 409 || error.statusCode == 503) {
            // A race/uncertain creation must be rediscovered, never replayed,
            // overwritten, reset or treated as an authenticated success.
            _next = null;
            _password.clear();
            _confirm.clear();
          }
          if (error.statusCode == 403) {
            _next = null;
            _password.clear();
            _confirm.clear();
          }
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final busy = _busy || ref.watch(authControllerProvider).isLoading;
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
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colors.border),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'FIRESIDE GROUP ACCOUNT',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colors.textAccent),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _register
                                ? 'Set your password'
                                : 'Sign in to launch applications',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _next == null
                                ? 'Enter your work email to continue.'
                                : _register
                                ? 'Create a password for your eligible PI email.'
                                : 'Enter your existing Group password.',
                          ),
                          if (_message != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _message!,
                              style: TextStyle(
                                color: _error
                                    ? colors.statusBad
                                    : colors.statusGreen,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _email,
                            enabled: !busy,
                            readOnly: _next != null,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                            validator: (value) =>
                                value == null || !value.trim().contains('@')
                                ? 'Enter a valid email.'
                                : null,
                            onFieldSubmitted: (_) {
                              if (_next == null) _submit();
                            },
                          ),
                          if (_next != null) ...[
                            TextButton(
                              onPressed: busy ? null : _changeEmail,
                              child: const Text('Change email'),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _password,
                              enabled: !busy,
                              obscureText: true,
                              autofillHints: [
                                _register
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              decoration: InputDecoration(
                                labelText: _register
                                    ? 'New password'
                                    : 'Password',
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Enter your password.';
                                }
                                if (_register &&
                                    (value.length < 8 || value.length > 1024)) {
                                  return 'Use 8–1024 characters.';
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) {
                                if (!_register) _submit();
                              },
                            ),
                            if (!_register) _recoveryBlock(context, busy),
                            if (_register) ...[
                              const SizedBox(height: 15),
                              TextFormField(
                                controller: _confirm,
                                enabled: !busy,
                                obscureText: true,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Confirm password',
                                ),
                                validator: (value) => value != _password.text
                                    ? 'Passwords do not match.'
                                    : null,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                            ],
                          ],
                          const SizedBox(height: 22),
                          FilledButton(
                            onPressed: busy ? null : _submit,
                            child: Text(
                              busy
                                  ? 'Please wait…'
                                  : _next == null
                                  ? 'Continue'
                                  : _register
                                  ? 'Create account'
                                  : 'Sign In',
                            ),
                          ),
                        ],
                      ),
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

  Widget _recoveryBlock(BuildContext context, bool busy) {
    final colors = context.appColors;
    final seconds = _recoverySecondsLeft;
    final sent = _recoveryMessage != null && !_recoveryError;
    final label = _recovering
        ? 'Sending reset link…'
        : seconds > 0
        ? 'Resend link in ${seconds}s'
        : sent
        ? 'Resend reset link'
        : 'Forgot password?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('forgot-password'),
            onPressed: busy || _recovering || seconds > 0
                ? null
                : _forgotPassword,
            child: Text(label),
          ),
        ),
        if (_recoveryMessage != null)
          Container(
            key: const Key('recovery-status'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.ivory,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recoveryMessage!,
                  style: TextStyle(
                    color: _recoveryError
                        ? colors.statusBad
                        : colors.statusGreen,
                  ),
                ),
                if (!_recoveryError) ...[
                  const SizedBox(height: 6),
                  Text(
                    SignInScreenRecoveryCopy.help,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
