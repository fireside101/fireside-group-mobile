import 'package:flutter_test/flutter_test.dart';

import 'package:fireside_group/features/app_viewer/app_webview_screen.dart';

void main() {
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
