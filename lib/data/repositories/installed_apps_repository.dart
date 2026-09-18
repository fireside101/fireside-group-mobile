import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which catalogue apps the user has installed so the Play Store style
/// detail button can show an "Already installed" state across launches.
class InstalledAppsRepository {
  const InstalledAppsRepository();

  static const _key = 'installed_apps';

  Future<SharedPreferences> _get() => SharedPreferences.getInstance();

  Future<Set<String>> read() async {
    final prefs = await _get();
    return (prefs.getStringList(_key) ?? const []).toSet();
  }

  Future<Set<String>> install(String appId) async {
    final prefs = await _get();
    final updated = (prefs.getStringList(_key) ?? const <String>[]).toSet()
      ..add(appId);
    await prefs.setStringList(_key, updated.toList());
    return updated;
  }
}