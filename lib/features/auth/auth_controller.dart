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

  Future<void> _restore() async {
    final session = await _service.restoreSession();
    state = AsyncValue.data(session);
  }

  Future<bool> signIn() async {
    try {
      final session = await _service.signIn();
      if (session != null) {
        state = AsyncValue.data(session);
        return true;
      }
      return false;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
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

final authControllerProvider = StateNotifierProvider<AuthController, AsyncValue<AuthSession?>>(
  (ref) => AuthController(ref.watch(authServiceProvider)),
);