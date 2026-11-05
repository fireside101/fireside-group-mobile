import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireside_group/data/services/app_update_service.dart';
import 'package:fireside_group/data/services/update_schedule.dart';

// Synthetic, credential-free host disk adapter. This is not Android DataStore.
class DiskScheduleStore implements ScheduleStore {
  DiskScheduleStore(this.path);
  final String path;
  @override
  Future<Map<String, dynamic>?> read() async => File(path).existsSync()
      ? jsonDecode(await File(path).readAsString()) as Map<String, dynamic>
      : null;
  @override
  Future<void> write(Map<String, dynamic> state) async {
    await File('$path.new').writeAsString(jsonEncode(state), flush: true);
    await File('$path.new').rename(path);
  }
}

Future<void> interruptedCheck(List<Object> args) async {
  final port = args[0] as SendPort;
  final path = args[1] as String;
  final schedule = UpdateSchedule(
    store: DiskScheduleStore(path),
    clock: () => DateTime.utc(2026),
  );
  await schedule.run(() async {
    port.send('reserved-before-request');
    await Completer<void>().future;
    return const AppUpdateCheckResult.none();
  });
}

void main() {
  test(
    'killed host isolate leaves disk reservation that suppresses restart IO',
    () async {
      final root = await Directory(
        Platform.environment['TMPDIR'] ?? Directory.current.path,
      ).createTemp('updater-schedule-host-');
      final path = '${root.path}/schedule.json';
      final store = DiskScheduleStore(path);
      await store.write({'due': 0, 'failures': 0});
      final port = ReceivePort();
      Isolate? isolate;
      try {
        isolate = await Isolate.spawn(interruptedCheck, [port.sendPort, path]);
        expect(
          await port.first.timeout(const Duration(seconds: 10)),
          'reserved-before-request',
        );
        isolate.kill(priority: Isolate.immediate);
        final now = DateTime.utc(2026);
        final restarted = UpdateSchedule(
          store: DiskScheduleStore(path),
          clock: () => now,
        );
        expect(await restarted.nextDue(), now.add(const Duration(minutes: 15)));
        var requests = 0;
        expect(
          await restarted.run(() async {
            requests++;
            return const AppUpdateCheckResult.none();
          }),
          isNull,
        );
        expect(requests, 0);
        expect(
          (await store.read())!.keys,
          unorderedEquals(['due', 'failures']),
        );
      } finally {
        isolate?.kill(priority: Isolate.immediate);
        port.close();
        await root.delete(recursive: true);
      }
    },
  );

  for (final maximum in [false, true]) {
    test(
      'successful check persists inclusive ${maximum ? 6 : 2}h deadline on disk',
      () async {
        final root = await Directory(
          Platform.environment['TMPDIR'] ?? Directory.current.path,
        ).createTemp('updater-jitter-host-');
        final path = '${root.path}/schedule.json';
        final now = DateTime.utc(2026);
        try {
          final schedule = UpdateSchedule(
            store: DiskScheduleStore(path),
            clock: () => now,
            randomInt: (n) => maximum ? n - 1 : 0,
          );
          await schedule.run(
            () async => const AppUpdateCheckResult.none(),
            manual: true,
          );
          final restarted = UpdateSchedule(
            store: DiskScheduleStore(path),
            clock: () => now,
          );
          expect(
            await restarted.nextDue(),
            now.add(Duration(hours: maximum ? 6 : 2)),
          );
          expect((await DiskScheduleStore(path).read())!['failures'], 0);
        } finally {
          await root.delete(recursive: true);
        }
      },
    );
  }
}
