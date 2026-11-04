import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireside_group/features/app_viewer/trusted_camera_permission.dart';
import 'package:fireside_group/features/app_viewer/webview_security.dart';

void main() {
  WebViewSecurity trusted() => WebViewSecurity('attendance-ptw')
    ..accountChanged('alice')
    ..pageFinished('https://ptw.firesideafrica.cloud/?source=tbt');

  test(
    'only approved requesting origin and camera-only request prompts runtime',
    () async {
      for (final origin in [
        null,
        'https://evil.test',
        'http://ptw.firesideafrica.cloud',
        'https://ptw.firesideafrica.cloud:444',
        'https://x@ptw.firesideafrica.cloud',
        'https://ptw.firesideafrica.cloud',
      ]) {
        for (final cameraOnly in [false, true]) {
          var prompted = false;
          var granted = false;
          var denied = false;
          await handleTrustedCameraPermission(
            security: trusted(),
            sourceOrigin: origin,
            cameraOnly: cameraOnly,
            requestRuntime: () async {
              prompted = true;
              return true;
            },
            isMounted: () => true,
            grant: () async {
              granted = true;
            },
            deny: () async {
              denied = true;
            },
          );
          final allowed =
              origin == 'https://ptw.firesideafrica.cloud' && cameraOnly;
          expect(prompted, allowed);
          expect(granted, allowed);
          expect(denied, !allowed);
        }
      }
    },
  );

  test('navigation account switch disposal and denied runtime cannot grant a pending request', () async {
    for (final change in [
      'navigation',
      'account',
      'logout',
      'dispose',
      'denied',
      'unmounted',
    ]) {
      final security = trusted();
      final permission = Completer<bool>();
      var granted = false;
      var denied = false;
      var mounted = true;
      final pending = handleTrustedCameraPermission(
        security: security,
        sourceOrigin: 'https://ptw.firesideafrica.cloud',
        cameraOnly: true,
        requestRuntime: () => permission.future,
        isMounted: () => mounted,
        grant: () async {
          granted = true;
        },
        deny: () async {
          denied = true;
        },
      );
      switch (change) {
        case 'navigation':
          security.navigationStarted();
        case 'account':
          security.accountChanged('bob');
        case 'logout':
          security.accountChanged(null);
        case 'dispose':
          security.close();
        case 'unmounted':
          mounted = false;
      }
      permission.complete(change != 'denied');
      await pending;
      expect(granted, false, reason: change);
      expect(denied, true, reason: change);
    }
  });
}
