import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

class AuthController extends StateNotifier<AsyncValue<AuthSession?>> {
  AuthController(this._service) : super(const AsyncValue.loading()) {
    _restore();
  }

  final AuthService _service;

  bool get isAuthenticated =>
      state.hasValue && state.value != null && !state.isLoading;

  Future<void> refresh() => _restore();

  Future<void> _restore() async {
    try {
      final session = await _service.restoreSession();
      state = AsyncValue.data(session);
    } catch (_) {
      // A stale or corrupt session must not prevent the login screen from
      // rendering. Treat it as signed out and let the user authenticate again.
      state = const AsyncValue.data(null);
    }
  }

  Future<bool> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final session = await _service.signIn(email: email, password: password);
      if (session != null) {
        state = AsyncValue.data(session);
        return true;
      }
      state = const AsyncValue.data(null);
      return false;
    } catch (error, stack) {
      // Keep routing in the signed-out state. The screen owns the
      // user-facing error and catches the exception at the button boundary.
      state = const AsyncValue.data(null);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<bool> register(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final session = await _service.register(email: email, password: password);
      state = AsyncValue.data(session);
      return session != null;
    } catch (error, stack) {
      state = const AsyncValue.data(null);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<bool> sendPasswordReset(String email) async {
    try {
      await _service.sendPasswordReset(email);
      return true;
    } catch (error, stack) {
      // Reset-email failures are displayed by the login screen and should not
      // replace the current auth state or trigger a router redirect.
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> signOut() async {
    try {
      await _service.signOut();
    } finally {
      state = const AsyncValue.data(null);
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AuthSession?>>(
      (ref) => AuthController(ref.watch(authServiceProvider)),
    );
