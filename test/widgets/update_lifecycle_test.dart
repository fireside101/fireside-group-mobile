import 'package:fireside_group/app.dart';
import 'package:fireside_group/core/router/app_router.dart';
import 'package:fireside_group/data/providers.dart';
import 'package:fireside_group/data/services/app_update_service.dart';
import 'package:fireside_group/data/services/update_background_wakeup.dart';
import 'package:fireside_group/data/services/update_runtime.dart';
import 'package:fireside_group/data/services/update_schedule.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'production lifecycle defers first check and catches up only on resume',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var now = DateTime.now();
      final service = RecordingUpdateService();
      final wakeup = RecordingWakeup();
      final schedule = UpdateSchedule(
        store: TestStore(),
        clock: () => now,
        randomInt: (_) => 0,
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Home')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerProvider.overrideWithValue(router),
            appUpdateServiceProvider.overrideWithValue(service),
            updateScheduleProvider.overrideWithValue(schedule),
            updateBackgroundWakeupProvider.overrideWithValue(wakeup),
            updateRuntimeConfigProvider.overrideWithValue(
              const UpdateRuntimeConfig(mode: 'github'),
            ),
          ],
          child: const FiresideGroupApp(),
        ),
      );
      await tester.pump();
      expect(service.checks, 0);
      expect(wakeup.registrations, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(hours: 3));
      await tester.pump(const Duration(hours: 3));
      expect(service.checks, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(service.checks, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(service.checks, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

class RecordingUpdateService extends AppUpdateService {
  int checks = 0;
  @override
  Future<AppUpdateCheckResult> checkForUpdate({
    bool automatic = false,
    bool force = false,
  }) async {
    checks++;
    return const AppUpdateCheckResult.none();
  }
}

class RecordingWakeup extends UpdateBackgroundWakeup {
  int registrations = 0;
  @override
  Future<void> register(Duration initialDelay) async {
    registrations++;
  }

  @override
  Future<bool> consumeReminder() async => false;
}

class TestStore implements ScheduleStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> state) async {
    value = state;
  }
}
