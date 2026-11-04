import 'package:flutter_test/flutter_test.dart';
import 'package:fireside_group/core/mobile_targets.dart';
import 'package:fireside_group/data/repositories/local_catalogue_repository.dart';
import 'package:fireside_group/features/app_viewer/webview_security.dart';
import 'package:fireside_group/features/app_viewer/app_webview_screen.dart';

MobileTargets devTargets({
  String tbt = MobileTargets.developmentTbtOrigin,
  String portal = MobileTargets.developmentPortalOrigin,
}) => MobileTargets(
  deploymentEnv: 'development',
  tbtBaseUrl: tbt,
  portalBaseUrl: portal,
);

void main() {
  test(
    'no overrides retains production; DEV rebinds only stable TBT entry',
    () {
      final prod = catalogueFor(MobileTargets());
      final dev = catalogueFor(devTargets());
      expect(prod.map((app) => app.id), dev.map((app) => app.id));
      final before = prod.singleWhere((app) => app.id == 'attendance-ptw');
      final after = dev.singleWhere((app) => app.id == before.id);
      expect(before.url, '${MobileTargets.productionTbtOrigin}/');
      expect(after.url, '${MobileTargets.developmentTbtOrigin}/');
      expect(after.healthUrl, '${MobileTargets.developmentTbtOrigin}/healthz');
      expect(
        after.copyWith(url: before.url, healthUrl: before.healthUrl),
        before,
      );
      expect(
        prod.where((a) => a.id != before.id),
        dev.where((a) => a.id != before.id),
      );
      expect(() => dev.clear(), throwsUnsupportedError);
    },
  );

  test('explicit mode and both matching reviewed origins are mandatory', () {
    for (final suffix in ['', '/']) {
      final prod = MobileTargets(
        portalBaseUrl: '${MobileTargets.productionPortalOrigin}$suffix',
        tbtBaseUrl: '${MobileTargets.productionTbtOrigin}$suffix',
      );
      expect(prod.isDevelopment, isFalse);
      expect(prod.portalOrigin, MobileTargets.productionPortalOrigin);
    }
    for (final bad in [
      'https://evil.test',
      '${MobileTargets.productionPortalOrigin}/api',
      '${MobileTargets.productionPortalOrigin}:443',
      MobileTargets.developmentPortalOrigin,
    ]) {
      expect(() => MobileTargets(portalBaseUrl: bad), throwsArgumentError);
    }
    expect(() => devTargets(tbt: ''), throwsArgumentError);
    expect(() => devTargets(portal: ''), throwsArgumentError);
    expect(
      () => MobileTargets(tbtBaseUrl: MobileTargets.developmentTbtOrigin),
      throwsArgumentError,
    );
    expect(
      () => MobileTargets(portalBaseUrl: MobileTargets.developmentPortalOrigin),
      throwsArgumentError,
    );
    for (final env in ['', 'dev', 'Development', 'staging', 'production ']) {
      expect(
        () => MobileTargets(deploymentEnv: env),
        throwsArgumentError,
        reason: env,
      );
    }
    expect(
      devTargets(tbt: '${MobileTargets.developmentTbtOrigin}/').isDevelopment,
      isTrue,
    );
    expect(
      devTargets(portal: '${MobileTargets.developmentPortalOrigin}/')
          .isDevelopment,
      isTrue,
    );
  });

  test(
    'arbitrary TBT or profile targets fail before networking or token access',
    () {
      for (final origin in [
        MobileTargets.developmentTbtOrigin,
        MobileTargets.developmentPortalOrigin,
      ]) {
        final host = Uri.parse(origin).host;
        for (final value in [
          '',
          'http://$host',
          'https://$host.evil.test',
          'https://evil.test',
          'https://user@$host',
          'https://$host:444',
          'https://$host:443',
          '$origin/path',
          '$origin?x=1',
          '$origin#fragment',
          '$origin//',
          ' $origin',
          'file:///etc/passwd',
          'javascript:alert(1)',
          MobileTargets.productionTbtOrigin,
          'https://firesidegroup.firesideafrica.cloud',
          'https://ptwapidev.firesideafrica.cloud',
        ]) {
          expect(
            () => origin == MobileTargets.developmentTbtOrigin
                ? devTargets(tbt: value)
                : devTargets(portal: value),
            throwsArgumentError,
            reason: value,
          );
        }
      }
    },
  );

  test('DEV bridge has no production fallback and retains lease isolation', () {
    final targets = devTargets();
    final policy = WebViewSecurity('attendance-ptw', targets: targets);
    const origin = MobileTargets.developmentTbtOrigin;
    for (final value in [
      MobileTargets.productionTbtOrigin,
      'https://ptwapidev.firesideafrica.cloud',
      '$origin.evil.test',
      '$origin:444',
      'http://ptwdev.firesideafrica.cloud',
      'https://user@ptwdev.firesideafrica.cloud',
    ]) {
      expect(policy.allows(value), isFalse, reason: value);
    }
    policy.accountChanged('synthetic-account');
    policy.pageFinished('$origin/?source=tbt');
    final capability = policy.documentCapability!;
    final lease = policy.authorizeBridge(capability, 1);
    expect(policy.isCurrent(lease), isTrue);
    expect(policy.authorizeBridge(capability, 1), isNull);
    expect(policy.canUseNative(sourceOrigin: null), isFalse);
    expect(
      policy.canUseNative(sourceOrigin: MobileTargets.productionTbtOrigin),
      isFalse,
    );
    policy.navigationStarted();
    expect(policy.isCurrent(lease), isFalse);
    policy.pageFinished('${MobileTargets.productionTbtOrigin}/');
    expect(policy.documentCapability, isNull);
    policy.pageFinished('$origin/');
    policy.accountChanged(null);
    expect(policy.captureLease(), isNull);
    policy.close();
    expect(policy.allows('$origin/'), isFalse);
    expect(
      WebViewSecurity('unknown', targets: targets).allows('$origin/'),
      isFalse,
    );
  });

  test('DEV landing keeps email/session gateway and legacy history URLs', () {
    final targets = devTargets();
    const origin = MobileTargets.developmentTbtOrigin;
    expect(usesMobileGatewayFor('attendance-ptw'), isTrue);
    expect(mobileGatewayPathFor('attendance-ptw'), '/auth/fireside/mobile');
    expect(
      tbtLandingRedirect(
        'attendance-ptw',
        '$origin/?email=a%40example.test',
        targets: targets,
      ).toString(),
      '$origin/?email=a%40example.test&source=tbt',
    );
    for (final path in [
      '/?source=ptw',
      '/?source=tbt',
      '/history?source=ptw',
      '/auth/fireside/mobile',
      '/login',
    ]) {
      expect(
        tbtLandingRedirect('attendance-ptw', '$origin$path', targets: targets),
        isNull,
      );
    }
    expect(
      tbtLandingRedirect(
        'attendance-ptw',
        '${MobileTargets.productionTbtOrigin}/',
        targets: targets,
      ),
      isNull,
    );
  });
}
