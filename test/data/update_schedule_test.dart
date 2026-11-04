import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireside_group/data/services/update_schedule.dart';
import 'package:fireside_group/data/services/app_update_service.dart';

import 'secure_update_auth_test.dart' show MemoryGate;

void main() {
  test(
    'two engines serialize a due check and reload the shared deadline',
    () async {
      final store = MemoryScheduleStore()..value = {'due': 0, 'failures': 0};
      final gate = MemoryGate();
      final now = DateTime.utc(2026);
      final first = UpdateSchedule(
        store: store,
        gate: gate,
        clock: () => now,
        randomInt: (_) => 0,
      );
      final second = UpdateSchedule(
        store: store,
        gate: gate,
        clock: () => now,
        randomInt: (_) => 0,
      );
      await second
          .nextDue(); // Cache the old deadline before the other engine runs.
      var checks = 0;
      Future<AppUpdateCheckResult> check() async {
        checks++;
        return const AppUpdateCheckResult.none();
      }

      await Future.wait([first.run(check), second.run(check)]);
      expect(checks, 1);
      expect(await second.nextDue(), now.add(const Duration(hours: 2)));
    },
  );
  test(
    'retry state survives restart and exponential delay caps at six hours',
    () async {
      var now = DateTime.utc(2026);
      final store = MemoryScheduleStore();
      var schedule = UpdateSchedule(
        store: store,
        clock: () => now,
        randomInt: (_) => 0,
      );
      for (var attempt = 0; attempt < 12; attempt++) {
        await schedule.run(
          () async => const AppUpdateCheckResult.unavailable('offline'),
          manual: true,
        );
        schedule = UpdateSchedule(
          store: store,
          clock: () => now,
          randomInt: (_) => 0,
        );
      }
      expect(await schedule.nextDue(), now.add(const Duration(hours: 6)));
    },
  );
  test('corrupt persisted state refuses an automatic network check', () async {
    final store = MemoryScheduleStore()..value = {'due': 'bad', 'failures': -1};
    final schedule = UpdateSchedule(store: store);
    var calls = 0;
    await expectLater(
      schedule.run(() async {
        calls++;
        return const AppUpdateCheckResult.none();
      }),
      throwsFormatException,
    );
    expect(calls, 0);
  });
  test('initial jitter is durable across scheduler recreation', () async {
    final store = MemoryScheduleStore();
    final now = DateTime.utc(2026);
    final first = UpdateSchedule(
      store: store,
      clock: () => now,
      randomInt: (_) => 0,
    );
    expect(await first.nextDue(), now.add(const Duration(hours: 2)));
    final second = UpdateSchedule(
      store: store,
      clock: () => now,
      randomInt: (n) => n - 1,
    );
    expect(await second.nextDue(), now.add(const Duration(hours: 2)));
  });
  test('initial jitter includes six hours', () async {
    final now = DateTime.utc(2026);
    final schedule = UpdateSchedule(
      store: MemoryScheduleStore(),
      clock: () => now,
      randomInt: (n) => n - 1,
    );
    expect(await schedule.nextDue(), now.add(const Duration(hours: 6)));
  });
  test(
    'automatic due checks retry exponentially and reset after success',
    () async {
      var now = DateTime.utc(2026);
      final schedule = UpdateSchedule(
        store: MemoryScheduleStore(),
        clock: () => now,
        randomInt: (_) => 0,
      );
      await schedule.nextDue();
      var calls = 0;
      Future<AppUpdateCheckResult> check() async {
        calls++;
        return const AppUpdateCheckResult.unavailable('offline');
      }

      expect(await schedule.run(check), isNull);
      now = now.add(const Duration(hours: 2));
      await schedule.run(check);
      expect(calls, 1);
      expect(await schedule.nextDue(), now.add(const Duration(minutes: 15)));
      now = now.add(const Duration(minutes: 15));
      await schedule.run(check);
      expect(await schedule.nextDue(), now.add(const Duration(minutes: 30)));
      await schedule.run(
        () async => const AppUpdateCheckResult.none(),
        manual: true,
      );
      expect(await schedule.nextDue(), now.add(const Duration(hours: 2)));
    },
  );
  test('manual checks bypass due time and concurrent calls coalesce', () async {
    final schedule = UpdateSchedule(
      store: MemoryScheduleStore(),
      randomInt: (_) => 0,
    );
    final pending = Completer<AppUpdateCheckResult>();
    var calls = 0;
    Future<AppUpdateCheckResult> check() {
      calls++;
      return pending.future;
    }

    final one = schedule.run(check, manual: true);
    final two = schedule.run(check, manual: true);
    pending.complete(const AppUpdateCheckResult.none());
    await Future.wait([one, two]);
    expect(calls, 1);
  });
  test('download jitter bounds and manual urgency', () {
    expect(
      downloadJitter(manual: true, randomInt: (n) => n - 1),
      Duration.zero,
    );
    expect(downloadJitter(manual: false, randomInt: (_) => 0), Duration.zero);
    expect(
      downloadJitter(manual: false, randomInt: (n) => n - 1),
      const Duration(minutes: 30),
    );
  });
}

class MemoryScheduleStore implements ScheduleStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> state) async {
    value = state;
  }
}
