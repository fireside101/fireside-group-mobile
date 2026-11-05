import 'dart:async';

import 'package:fireside_group/data/services/auth_service.dart';
import 'package:fireside_group/features/auth/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class DelayedAuth extends AuthService {
  final old = Completer<AuthSession?>();
  final newer = Completer<AuthSession?>();
  @override
  Future<AuthSession?> restoreSession() async => null;
  @override
  Future<AuthSession?> signIn({
    required String email,
    required String password,
  }) => email == 'old@example.test' ? old.future : newer.future;
  @override
  Future<void> signOut() async {}
}

void main() {
  test('late failed old login cannot clear newer account state', () async {
    final service = DelayedAuth();
    final controller = AuthController(service);
    await Future<void>.delayed(Duration.zero);
    final old = controller.signIn('old@example.test', 'test-password');
    final newer = controller.signIn('new@example.test', 'test-password');
    service.newer.complete(
      const AuthSession(name: 'New', email: 'new@example.test'),
    );
    expect(await newer, isTrue);
    service.old.completeError(StateError('Superseded'));
    await expectLater(old, throwsStateError);
    expect(controller.state.value?.email, 'new@example.test');
    controller.dispose();
  });
  test('late login cannot overwrite logout', () async {
    final service = DelayedAuth();
    final controller = AuthController(service);
    await Future<void>.delayed(Duration.zero);
    final old = controller.signIn('old@example.test', 'test-password');
    await controller.signOut();
    service.old.complete(
      const AuthSession(name: 'Old', email: 'old@example.test'),
    );
    expect(await old, isFalse);
    expect(controller.state.value, isNull);
    controller.dispose();
  });
}
