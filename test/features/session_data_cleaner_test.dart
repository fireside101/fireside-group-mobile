import 'dart:async';

import 'package:fireside_group/data/providers.dart';
import 'package:fireside_group/data/repositories/recent_apps_repository.dart';
import 'package:fireside_group/data/services/auth_service.dart';
import 'package:fireside_group/data/services/profile_service.dart';
import 'package:fireside_group/data/services/session_data_cleaner.dart';
import 'package:fireside_group/features/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAuth extends AuthService {
  FakeAuth(this.log);
  final List<String> log;
  @override
  Future<AuthSession?> restoreSession() async => null;
  @override
  Future<AuthSession?> signIn({
    required String email,
    required String password,
  }) async {
    log.add('signIn');
    return AuthSession(name: 'N', email: email);
  }

  @override
  Future<void> signOut() async => log.add('signOut');
}

class SlowRecentApps extends RecentAppsRepository {
  final pendingRead = Completer<List<String>>();
  bool cleared = false;
  @override
  Future<List<String>> read() => pendingRead.future;
  @override
  Future<void> clear() async => cleared = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every purge step runs even when an earlier one fails', () async {
    final ran = <String>[];
    await SessionDataCleaner([
      () async => throw StateError('no webview platform'),
      () async => ran.add('profile'),
      () async => ran.add('recent'),
    ]).purge();
    expect(ran, ['profile', 'recent']);
  });

  test('sign-out purges after the session ends', () async {
    final log = <String>[];
    final controller = AuthController(
      FakeAuth(log),
      cleaner: SessionDataCleaner([() async => log.add('purge')]),
    );
    await Future<void>.delayed(Duration.zero);
    await controller.signOut();
    expect(log, ['signOut', 'purge']);
    expect(controller.state.value, isNull);
    controller.dispose();
  });

  test('sign-in (account change) purges before the new session', () async {
    final log = <String>[];
    final controller = AuthController(
      FakeAuth(log),
      cleaner: SessionDataCleaner([() async => log.add('purge')]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(await controller.signIn('b@example.test', 'pw'), isTrue);
    expect(log, ['purge', 'signIn']);
    controller.dispose();
  });

  test('recent apps are cleared', () async {
    SharedPreferences.setMockInitialValues({});
    const repository = RecentAppsRepository();
    await repository.record('warehouse');
    await repository.clear();
    expect(await repository.read(), isEmpty);
  });

  test('clear wins over a load that started before it', () async {
    final repository = SlowRecentApps();
    final container = ProviderContainer(
      overrides: [recentAppsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(recentAppsProvider.notifier);
    await notifier.clear();
    repository.pendingRead.complete(['warehouse']);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(container.read(recentAppsProvider).value, isEmpty);
    expect(repository.cleared, isTrue);
  });

  test(
    'profile cache clear removes every user profile and nothing else',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'profile_cache_user-a': '{}',
        'profile_cache_user-b': '{}',
        'unrelated_secret': 'keep',
      });
      const storage = FlutterSecureStorage();
      final notifier = ProfileCacheNotifier(ProfileService(), storage: storage);
      await notifier.clearAll();
      expect(await storage.readAll(), {'unrelated_secret': 'keep'});
      expect(notifier.state.value, isNull);
      notifier.dispose();
    },
  );
}
