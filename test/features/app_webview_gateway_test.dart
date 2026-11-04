import 'package:flutter_test/flutter_test.dart';

import 'package:fireside_group/features/app_viewer/app_webview_screen.dart';

void main() {
  test('PTW root after SSO lands on explicit unified TBT route without changing gateway', () {
    expect(
      tbtLandingRedirect(
        'attendance-ptw',
        'https://ptw.firesideafrica.cloud/',
      ).toString(),
      'https://ptw.firesideafrica.cloud/?source=tbt',
    );
    expect(
      tbtLandingRedirect(
        'attendance-ptw',
        'https://ptw.firesideafrica.cloud/?source=tbt',
      ),
      isNull,
    );
    expect(
      tbtLandingRedirect(
        'attendance-ptw',
        'https://ptw.firesideafrica.cloud/?source=ptw',
      ),
      isNull,
    );
    expect(
      tbtLandingRedirect('attendance-ptw', 'https://evil.example/'),
      isNull,
    );
    expect(
      tbtLandingRedirect('warehouse', 'https://ptw.firesideafrica.cloud/'),
      isNull,
    );
  });
  test('uses the PTW SSO gateway route exposed by its frontend proxy', () {
    expect(mobileGatewayPathFor('attendance-ptw'), '/auth/fireside/mobile');
  });

  test('keeps the maintenance tracker SSO gateway route', () {
    expect(mobileGatewayPathFor('maintenance-tracker'), '/api/auth/sso/mobile');
  });

  test('uses the Fuel Control System mobile gateway route', () {
    expect(
      mobileGatewayPathFor('fuel-control-system'),
      '/api/v1/auth/fireside/mobile',
    );
  });

  test('uses the FleetNow mobile gateway route', () {
    expect(mobileGatewayPathFor('fleetnow'), '/api/auth/sso/fireside/mobile');
  });
}
