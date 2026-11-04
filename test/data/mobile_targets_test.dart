import 'package:flutter_test/flutter_test.dart';
import 'package:fireside_group/data/repositories/local_catalogue_repository.dart';
import 'package:fireside_group/features/app_viewer/webview_security.dart';
import 'package:fireside_group/features/app_viewer/app_webview_screen.dart';

void main() {
  const dev = String.fromEnvironment('MOBILE_DEPLOYMENT_ENV') == 'development';
  final origin = dev
      ? 'https://ptwdev.firesideafrica.cloud'
      : 'https://ptw.firesideafrica.cloud';
  final other = dev
      ? 'https://ptw.firesideafrica.cloud'
      : 'https://ptwdev.firesideafrica.cloud';

  test(
    'compiled catalogue and repository select only the configured TBT target',
    () async {
      final app = catalogue.singleWhere((app) => app.id == 'attendance-ptw');
      expect(app.url, '$origin/');
      expect(app.healthUrl, '$origin/healthz');
      expect(app.repository, 'attendance-ptw');
      expect(await LocalCatalogueRepository().fetchCatalogue(), catalogue);
    },
  );

  test('compiled bearer and native policy trust only the selected origin', () {
    final policy = WebViewSecurity('attendance-ptw');
    expect(policy.allows('$origin/auth/fireside/mobile'), isTrue);
    expect(policy.allows('$other/auth/fireside/mobile'), isFalse);
    policy.accountChanged('synthetic-account');
    policy.pageFinished('$origin/?source=tbt');
    expect(policy.documentCapability, isNotNull);
    expect(policy.canUseNative(sourceOrigin: origin), isTrue);
    expect(policy.canUseNative(sourceOrigin: other), isFalse);
    policy.pageFinished('$other/');
    expect(policy.documentCapability, isNull);
  });

  test(
    'compiled landing selects TBT but leaves historical PTW source intact',
    () {
      expect(
        tbtLandingRedirect('attendance-ptw', '$origin/').toString(),
        '$origin/?source=tbt',
      );
      expect(
        tbtLandingRedirect('attendance-ptw', '$origin/?source=ptw'),
        isNull,
      );
      expect(tbtLandingRedirect('attendance-ptw', '$other/'), isNull);
      expect(mobileGatewayPathFor('attendance-ptw'), '/auth/fireside/mobile');
    },
  );
}
