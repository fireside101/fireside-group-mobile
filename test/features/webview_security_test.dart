import 'package:flutter_test/flutter_test.dart';
import 'package:fireside_group/features/app_viewer/webview_security.dart';

void main() {
  test(
    'only an approved document gets an unguessable one-use bridge capability',
    () {
      final warehouse = WebViewSecurity('warehouse');
      warehouse.accountChanged('alice');
      warehouse.pageFinished('https://warehouse.firesideafrica.cloud');
      expect(warehouse.documentCapability, isNull);
      expect(
        warehouse.canUseNative(
          sourceOrigin: 'https://warehouse.firesideafrica.cloud',
        ),
        isFalse,
      );
      final policy = WebViewSecurity('attendance-ptw');
      policy.accountChanged('alice');
      policy.pageFinished('https://evil.test');
      expect(policy.documentCapability, isNull);
      policy.pageFinished('https://ptw.firesideafrica.cloud/form');
      final capability = policy.documentCapability!;
      expect(capability.length, greaterThanOrEqualTo(32));
      expect(policy.authorizeBridge('guessed', 1), isNull);
      final lease = policy.authorizeBridge(capability, 1);
      expect(policy.isCurrent(lease), isTrue);
      expect(policy.authorizeBridge(capability, 1), isNull);
      policy.navigationStarted();
      expect(policy.authorizeBridge(capability, 2), isNull);
      expect(policy.isCurrent(lease), isFalse);
      policy.pageFinished('https://ptw.firesideafrica.cloud/form');
      expect(policy.documentCapability, isNot(capability));
      policy.accountChanged(null);
      expect(policy.documentCapability, isNull);
    },
  );

  test('catalogue cannot redirect bearer tokens to a lookalike origin', () {
    final policy = WebViewSecurity('attendance-ptw');
    expect(policy.allows('https://ptw.firesideafrica.cloud/form'), isTrue);
    expect(policy.allows('https://ptw.firesideafrica.cloud:443/form'), isTrue);
    for (final url in [
      'http://ptw.firesideafrica.cloud',
      'https://ptw.firesideafrica.cloud.evil.test',
      'https://ptw.firesideafrica.cloud:444',
      'https://user@ptw.firesideafrica.cloud',
      'https://warehouse.firesideafrica.cloud',
      'file:///etc/passwd',
      'javascript:alert(1)',
      'data:text/html,hello',
    ]) {
      expect(policy.allows(url), isFalse, reason: url);
    }
    expect(
      WebViewSecurity('unknown').allows('https://ptw.firesideafrica.cloud'),
      isFalse,
    );
  });

  test(
    'navigation account change logout and disposal invalidate camera leases',
    () {
      for (final change in ['navigation', 'account', 'logout', 'dispose']) {
        final policy = WebViewSecurity('attendance-ptw');
        policy.accountChanged('alice');
        policy.navigationStarted();
        policy.pageFinished('https://ptw.firesideafrica.cloud/form');
        final lease = policy.captureLease();
        expect(policy.isCurrent(lease), isTrue);
        switch (change) {
          case 'navigation':
            policy.navigationStarted();
          case 'account':
            policy.accountChanged('bob');
          case 'logout':
            policy.accountChanged(null);
          case 'dispose':
            policy.close();
        }
        expect(policy.isCurrent(lease), isFalse, reason: change);
      }
    },
  );

  test(
    'unknown frame provenance cannot invoke native bridge or permissions',
    () {
      final policy = WebViewSecurity('attendance-ptw');
      policy.accountChanged('alice');
      policy.pageFinished('https://ptw.firesideafrica.cloud');
      expect(policy.canUseNative(sourceOrigin: null), isFalse);
      expect(policy.canUseNative(sourceOrigin: 'https://evil.test'), isFalse);
      expect(
        policy.canUseNative(sourceOrigin: 'https://ptw.firesideafrica.cloud'),
        isTrue,
      );
      policy.accountChanged(null);
      expect(
        policy.canUseNative(sourceOrigin: 'https://ptw.firesideafrica.cloud'),
        isFalse,
      );
    },
  );
}
