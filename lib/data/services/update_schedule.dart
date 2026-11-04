import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_service.dart';
import 'secure_update_auth.dart';

abstract interface class ScheduleStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> state);
}

/// Contains only scheduling times/counters, never sessions, URLs or credentials.
class PreferencesScheduleStore implements ScheduleStore {
  static const key = 'android_update_schedule_v1';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  @override
  Future<Map<String, dynamic>?> read() async {
    final raw = await _preferences.getString(key);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> write(Map<String, dynamic> state) =>
      _preferences.setString(key, jsonEncode(state));
}

Duration downloadJitter({required bool manual, int Function(int)? randomInt}) =>
    manual
    ? Duration.zero
    : Duration(seconds: (randomInt ?? Random.secure().nextInt)(1801));

/// Durable deadlines shared by foreground and background engines. Native
/// transactions serialize the complete due/reserve/check/commit operation.
class UpdateSchedule {
  UpdateSchedule({
    required this.store,
    DateTime Function()? clock,
    int Function(int)? randomInt,
    AuthGate? gate,
  }) : _clock = clock ?? DateTime.now,
       _gate =
           gate ??
           (store is PreferencesScheduleStore
               ? SqliteAuthGate(name: 'mobile_update_schedule_gate_v1')
               : null),
       _randomInt = randomInt ?? Random.secure().nextInt;
  final ScheduleStore store;
  final DateTime Function() _clock;
  final int Function(int) _randomInt;
  final AuthGate? _gate;
  Future<AppUpdateCheckResult?>? _inFlight;

  DateTime? _due;
  int _failures = 0;

  Future<T> _guard<T>(Future<T> Function() action) =>
      _gate?.run(action) ?? action();
  Future<void> _load() => _loadState();
  Future<void> _loadState() async {
    final state = await store.read();
    if (state != null) {
      final due = state['due'];
      final failures = state['failures'];
      if (due is! int || failures is! int || failures < 0 || failures > 10) {
        throw const FormatException('Invalid update scheduling state');
      }
      _due = DateTime.fromMillisecondsSinceEpoch(due, isUtc: true);
      _failures = failures;
    } else {
      _due = _clock().add(Duration(seconds: 7200 + _randomInt(14401)));
      await _save();
    }
  }

  Future<void> _save() =>
      store.write({'due': _due!.millisecondsSinceEpoch, 'failures': _failures});
  Future<DateTime> nextDue() => _guard(() async {
    await _load();
    return _due!;
  });

  Future<Duration> delayUntilDue() async {
    final remaining = (await nextDue()).difference(_clock());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<AppUpdateCheckResult?> run(
    Future<AppUpdateCheckResult> Function() check, {
    bool manual = false,
  }) {
    if (_inFlight != null) return _inFlight!;
    return _inFlight = _guard(() => _run(check, manual: manual))
        .whenComplete(() => _inFlight = null);
  }

  Future<AppUpdateCheckResult?> _run(
    Future<AppUpdateCheckResult> Function() check, {
    required bool manual,
  }) async {
    await _load();
    if (!manual && _clock().isBefore(_due!)) return null;
    // A crashed request cannot create a tight restart loop.
    _due = _clock().add(const Duration(minutes: 15));
    await _save();
    AppUpdateCheckResult result;
    try {
      result = await check();
    } catch (_) {
      result = const AppUpdateCheckResult.unavailable(
        'Updates could not be checked.',
      );
    }
    if (result.isUnavailable) {
      _failures = min(_failures + 1, 10);
      final minutes = min(15 * (1 << (_failures - 1)), 360);
      _due = _clock().add(Duration(minutes: minutes));
    } else {
      _failures = 0;
      _due = _clock().add(Duration(seconds: 7200 + _randomInt(14401)));
    }
    await _save();
    return result;
  }
}
