import 'package:webview_flutter/webview_flutter.dart';

/// One purge step. Steps are independent: a failing step never stops the rest.
typedef PurgeStep = Future<void> Function();

/// Clears everything a previous account could leave behind on this device:
/// WebView cookies, web storage and cache, and per-user caches (profile,
/// recent apps). Run on sign-out and before a new sign-in (account change).
class SessionDataCleaner {
  SessionDataCleaner(this._steps);

  final List<PurgeStep> _steps;

  Future<void> purge() async {
    for (final step in _steps) {
      try {
        await step();
      } catch (_) {
        // Best effort per step; never block sign-out on a platform failure.
      }
    }
  }
}

/// Clears cookies, localStorage/IndexedDB and the HTTP cache shared by every
/// WebView in this process. On Android, WebStorage and the cache are
/// process-wide, so a transient controller is enough when none is on screen.
Future<void> clearWebViewData({WebViewController? controller}) async {
  Object? failure;
  Future<void> attempt(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      failure ??= error;
    }
  }

  await attempt(() async => WebViewCookieManager().clearCookies());
  final target = controller ?? WebViewController();
  await attempt(target.clearLocalStorage);
  await attempt(target.clearCache);
  if (failure != null) throw failure!;
}
