import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fireside_group/data/services/update_background_wakeup.dart';
import 'package:fireside_group/data/services/update_runtime.dart';
import 'package:fireside_group/data/services/update_schedule.dart';

import 'secure_update_auth_test.dart' show MemorySecrets, MemoryGate, session;
import 'update_schedule_test.dart' show MemoryScheduleStore;

import 'package:fireside_group/data/services/secure_update_auth.dart';

const config = UpdateRuntimeConfig(
  mode: 'private',
  storageBase: 'https://supabase.firesideafrica.cloud/storage/v1/object/sign',
  supabaseUrl: 'https://supabase.firesideafrica.cloud',
  supabaseAnonKey: 'synthetic-anon',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('production callback refreshes encrypted session then makes private check; stores only reminder', () async {
    final secrets = MemorySecrets();
    final gate = MemoryGate();
    final foreground = SecureSessionVault(secrets: secrets, gate: gate);
    await foreground.acceptLogin(session('expired'));
    final worker = SecureSessionVault(secrets: secrets, gate: gate);
    final paths = <String>[];
    final reminders = <bool>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      expect(request.followRedirects, isFalse);
      if (request.url.path == '/auth/v1/token') {
        expect(jsonDecode(request.body)['refresh_token'], 'refresh-expired');
        return http.Response(
          jsonEncode({...session('fresh'), 'expires_at': 9999999999}),
          200,
        );
      }
      expect(request.headers['authorization'], 'Bearer fresh');
      return http.Response(
        jsonEncode({
          'release': {
            'provider': 'supabase-rest',
            'download_url': 'never-persist-me',
          },
        }),
        200,
      );
    });
    final scheduleStore = MemoryScheduleStore()
      ..value = {'due': 0, 'failures': 0};
    final dependencies = BackgroundUpdateDependencies(
      config: config,
      vault: worker,
      client: client,
      schedule: UpdateSchedule(store: scheduleStore, randomInt: (_) => 0),
      writeReminder: (value) async {
        reminders.add(value);
      },
    );
    expect(
      await executeUpdateWakeupTask(
        updateWakeupTask,
        null,
        dependencies: dependencies,
      ),
      isTrue,
    );
    expect(paths, ['/auth/v1/token', '/functions/v1/mobile-update']);
    expect(reminders, [true]);
    expect(jsonEncode(scheduleStore.value), isNot(contains('fresh')));
    expect(jsonEncode(secrets.values), isNot(contains('never-persist-me')));
    await executeUpdateWakeupTask(
      updateWakeupTask,
      null,
      dependencies: dependencies,
    );
    expect(paths.length, 2); // Same persisted deadline suppresses another wake.
  });
  test('callback has zero HTTP or reminders without Auth and ignores input credentials', () async {
    var calls = 0;
    final deps = BackgroundUpdateDependencies(
      config: config,
      vault: SecureSessionVault(secrets: MemorySecrets(), gate: MemoryGate()),
      client: MockClient((_) async {
        calls++;
        throw StateError('must not send');
      }),
      schedule: UpdateSchedule(
        store: MemoryScheduleStore()..value = {'due': 0, 'failures': 0},
      ),
      writeReminder: (_) async {
        throw StateError('must not persist');
      },
    );
    expect(
      await executeUpdateWakeupTask(updateWakeupTask, {
        'token': 'untrusted',
      }, dependencies: deps),
      isTrue,
    );
    expect(calls, 0);
  });
  test(
    'logout during real callback private request prevents pending reminder',
    () async {
      final secrets = MemorySecrets();
      final gate = MemoryGate();
      final vault = SecureSessionVault(secrets: secrets, gate: gate);
      await vault.acceptLogin({...session('valid'), 'expires_at': 9999999999});
      final entered = Completer<void>();
      final finish = Completer<void>();
      var reminders = 0;
      final deps = BackgroundUpdateDependencies(
        config: config,
        vault: vault,
        client: MockClient((_) async {
          entered.complete();
          await finish.future;
          return http.Response('{"release":null}', 200);
        }),
        schedule: UpdateSchedule(
          store: MemoryScheduleStore()..value = {'due': 0, 'failures': 0},
        ),
        writeReminder: (_) async {
          reminders++;
        },
      );
      final run = executeUpdateWakeupTask(
        updateWakeupTask,
        null,
        dependencies: deps,
      );
      await entered.future;
      await vault.removePersistedSession();
      finish.complete();
      expect(await run, isFalse);
      expect(reminders, 0);
    },
  );
}
