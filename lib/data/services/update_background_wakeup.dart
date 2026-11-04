import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app_update_service.dart';
import 'secure_update_auth.dart';
import 'update_runtime.dart';
import 'update_schedule.dart';

const legacyUpdateWakeupTask = 'fireside.update.foreground-reminder.v1';
const updateWakeupTask = 'fireside.update.authenticated-check.v2';
const updateWakeupKey = 'update_foreground_reminder_v1';

class BackgroundUpdateDependencies {
  BackgroundUpdateDependencies({
    required this.config,
    required this.vault,
    required this.client,
    required this.schedule,
    required this.writeReminder,
  });
  final UpdateRuntimeConfig config;
  final SecureSessionVault vault;
  final http.Client client;
  final UpdateSchedule schedule;
  final Future<void> Function(bool) writeReminder;
  factory BackgroundUpdateDependencies.production() =>
      BackgroundUpdateDependencies(
        config: const UpdateRuntimeConfig(),
        vault: SecureSessionVault.production(),
        client: http.Client(),
        schedule: UpdateSchedule(store: PreferencesScheduleStore()),
        writeReminder: (value) =>
            SharedPreferencesAsync().setBool(updateWakeupKey, value),
      );
}

/// The exact callback registered with WorkManager. No inputData is consumed:
/// credentials are read only from encrypted native storage, never task input.
/// Checks eligibility but never downloads an APK or launches an installer.
Future<bool> executeUpdateWakeupTask(
  String task,
  Map<String, dynamic>? inputData, {
  BackgroundUpdateDependencies? dependencies,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (task != updateWakeupTask) return true;
  final owned = dependencies == null;
  final deps = dependencies ?? BackgroundUpdateDependencies.production();
  try {
    if (!deps.config.backgroundReady) return true;
    await deps.vault.initialize();
    if (!await deps.vault.hasAccessToken()) return true;
    final epoch = deps.vault.binding;
    if (epoch == null) return true;
    final result = await deps.schedule.run(() async {
      await deps.vault.checkPrivate(
        deps.client,
        Uri.parse(deps.config.supabaseUrl),
        deps.config.supabaseAnonKey,
      );
      // Only a noncredential reminder survives. Foreground rechecks eligibility
      // before presenting/downloading anything; signed URLs are discarded here.
      await deps.vault.whileCurrent(epoch, () => deps.writeReminder(true));
      return const AppUpdateCheckResult.none();
    });
    return result == null || !result.isUnavailable;
  } catch (_) {
    // Never log SDK responses/exceptions (may contain credentials/signed URLs).
    return false;
  } finally {
    if (owned) deps.client.close();
  }
}

@pragma('vm:entry-point')
void updateWakeupDispatcher() {
  Workmanager().executeTask(executeUpdateWakeupTask);
}

class UpdateBackgroundWakeup {
  Future<void>? _initialization;
  Future<void> register(Duration initialDelay) =>
      _initialization ??= _register(initialDelay);
  Future<void> _register(Duration initialDelay) async {
    await Workmanager().initialize(updateWakeupDispatcher);
    await Workmanager().registerPeriodicTask(
      updateWakeupTask,
      updateWakeupTask,
      // 15-minute OS opportunities; durable randomized 2–6h deadlines decide
      // whether a request is actually due. WorkManager remains best-effort.
      frequency: const Duration(minutes: 15),
      initialDelay: initialDelay,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
    // KEEP cannot change the old 12h reminder's cadence. Enroll v2 first, then
    // retire v1; old callbacks are ignored and cannot perform authenticated IO.
    await Workmanager().cancelByUniqueName(legacyUpdateWakeupTask);
  }

  Future<bool> consumeReminder() async {
    final preferences = SharedPreferencesAsync();
    final pending = await preferences.getBool(updateWakeupKey) ?? false;
    if (pending) await preferences.setBool(updateWakeupKey, false);
    return pending;
  }
}
