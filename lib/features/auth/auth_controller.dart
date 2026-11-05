import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

class AuthController extends StateNotifier<AsyncValue<AuthSession?>> {
  AuthController(this._service) : super(const AsyncValue.loading()) {
    _restore();
  }
  final AuthService _service;
  int _operation = 0;
  bool get isAuthenticated =>
      state.hasValue && state.value != null && !state.isLoading;
  bool _current(int operation) => mounted && operation == _operation;
  Future<void> refresh() => _restore();
  Future<void> _restore() async {
    final operation = ++_operation;
    try {
      final session = await _service.restoreSession();
      if (_current(operation)) state = AsyncValue.data(session);
    } catch (_) {
      if (_current(operation)) state = const AsyncValue.data(null);
    }
  }

  Future<bool> signIn(String email, String password) async {
    final operation = ++_operation;
    state = const AsyncValue.loading();
    try {
      final session = await _service.signIn(email: email, password: password);
      if (!_current(operation)) return false;
      state = AsyncValue.data(session);
      return session != null;
    } catch (error, stack) {
      if (_current(operation)) state = const AsyncValue.data(null);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<bool> register(
    String email,
    String password,
    String confirmPassword,
  ) async {
    final operation = ++_operation;
    state = const AsyncValue.loading();
    try {
      await _service.register(
        email: email,
        password: password,
        confirmPassword: confirmPassword,
      );
      if (_current(operation)) state = const AsyncValue.data(null);
      return false; // Registration never signs in.
    } catch (error, stack) {
      if (_current(operation)) state = const AsyncValue.data(null);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<bool> sendPasswordReset(String email) async {
    await _service.sendPasswordReset(email);
    return true;
  }

  Future<void> signOut() async {
    final operation = ++_operation;
    try {
      await _service.signOut();
    } finally {
      if (_current(operation)) state = const AsyncValue.data(null);
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AuthSession?>>(
      (ref) => AuthController(ref.watch(authServiceProvider)),
    );
