/// Reviewed build-time targets, independent of app identity and local storage.
/// No debug/release heuristic and no remote host list can enable DEV trust.
class MobileTargets {
  MobileTargets({
    String deploymentEnv = 'production',
    String tbtBaseUrl = '',
    String portalBaseUrl = '',
  }) : isDevelopment = deploymentEnv == 'development' {
    if (deploymentEnv != 'production' && deploymentEnv != 'development') {
      throw ArgumentError('Unsupported MOBILE_DEPLOYMENT_ENV');
    }
    if (isDevelopment) {
      if (!_isRoot(tbtBaseUrl, developmentTbtOrigin) ||
          !_isRoot(portalBaseUrl, developmentPortalOrigin)) {
        throw ArgumentError(
          'DEV requires explicit reviewed TBT_BASE_URL and PORTAL_API_BASE_URL',
        );
      }
    } else if ((tbtBaseUrl.isNotEmpty &&
            !_isRoot(tbtBaseUrl, productionTbtOrigin)) ||
        (portalBaseUrl.isNotEmpty &&
            !_isRoot(portalBaseUrl, productionPortalOrigin))) {
      // A DEV portal alone must not leave the TBT tile pointing to production.
      throw ArgumentError(
        'Production accepts only reviewed production origins',
      );
    }
  }

  factory MobileTargets.fromEnvironment() => MobileTargets(
    deploymentEnv: const String.fromEnvironment(
      'MOBILE_DEPLOYMENT_ENV',
      defaultValue: 'production',
    ),
    tbtBaseUrl: const String.fromEnvironment('TBT_BASE_URL'),
    portalBaseUrl: const String.fromEnvironment('PORTAL_API_BASE_URL'),
  );

  static const productionTbtOrigin = 'https://ptw.firesideafrica.cloud';
  static const productionPortalOrigin =
      'https://firesidegroup.firesideafrica.cloud';
  // attendance-modernization/frontend/deploy-dev/ingressroute-tls.yaml
  static const developmentTbtOrigin = 'https://ptwdev.firesideafrica.cloud';
  static const developmentPortalOrigin =
      'https://firesidegroupdev.firesideafrica.cloud';

  final bool isDevelopment;
  String get tbtOrigin =>
      isDevelopment ? developmentTbtOrigin : productionTbtOrigin;
  String get portalOrigin =>
      isDevelopment ? developmentPortalOrigin : productionPortalOrigin;

  static bool _isRoot(String value, String origin) =>
      value == origin || value == '$origin/';
}
