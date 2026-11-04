import 'webview_security.dart';

/// The requesting frame's native origin is mandatory, never the top URL alone.
/// Recheck the document/account lease after the Android permission dialog.
Future<void> handleTrustedCameraPermission({
  required WebViewSecurity security,
  required String? sourceOrigin,
  required bool cameraOnly,
  required Future<bool> Function() requestRuntime,
  required bool Function() isMounted,
  required Future<void> Function() grant,
  required Future<void> Function() deny,
}) async {
  final lease = security.captureLease();
  if (!cameraOnly ||
      !isMounted() ||
      !security.canUseNative(sourceOrigin: sourceOrigin)) {
    await deny();
    return;
  }
  try {
    final allowed = await requestRuntime();
    if (allowed &&
        isMounted() &&
        security.isCurrent(lease) &&
        security.canUseNative(sourceOrigin: sourceOrigin)) {
      await grant();
      return;
    }
  } catch (_) {
    // Cancellation and platform permission errors fail closed.
  }
  await deny();
}
