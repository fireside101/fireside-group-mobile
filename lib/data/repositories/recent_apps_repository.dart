import 'package:shared_preferences/shared_preferences.dart';

/// Stores the most recently opened app ids, most-recent-first, de-duplicated,
/// capped at [maxEntries]. Mirrors the web app's `use-recent-apps` hook.
class RecentAppsRepository {
  const RecentAppsRepository();

  static const _key = 'recent_apps';
  static const int maxEntries = 6;

  Future<SharedPreferences> _get() => SharedPreferences.getInstance();

  Future<List<String>> read() async {
    final prefs = await _get();
    return prefs.getStringList(_key) ?? const [];
  }

  /// Recent apps reveal what a person used; they are cleared on account change.
  Future<void> clear() async {
    final prefs = await _get();
    await prefs.remove(_key);
  }

  Future<List<String>> record(String appId) async {
    final prefs = await _get();
    final current = prefs.getStringList(_key) ?? const <String>[];
    final updated = current.where((id) => id != appId).toList()
      ..insert(0, appId);
    final trimmed = updated.length > maxEntries
        ? updated.sublist(0, maxEntries)
        : updated;
    await prefs.setStringList(_key, trimmed);
    return trimmed;
  }
}
