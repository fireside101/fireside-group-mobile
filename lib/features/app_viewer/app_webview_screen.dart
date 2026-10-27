import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/fireside_application.dart';
import '../../data/models/health_status.dart';
import '../../data/providers.dart';
import '../app_card/app_icon_map.dart';
import '../app_card/status_indicator.dart';

bool usesMobileGatewayFor(String appId) => const {
  'scorecard',
  'warehouse',
  'tadhkara',
  'maintenance-tracker',
  'attendance-ptw',
  'fuel-control-system',
  'fleetnow',
}.contains(appId);

String mobileGatewayPathFor(String appId) {
  if (appId == 'maintenance-tracker') {
    // Maintenance Tracker exposes its backend SSO route behind the frontend
    // proxy at /api/auth/sso/mobile.
    return '/api/auth/sso/mobile';
  }
  if (appId == 'attendance-ptw') {
    // PTW explicitly proxies this non-API path to its attendance backend.
    return '/auth/fireside/mobile';
  }
  if (appId == 'fuel-control-system') {
    return '/api/v1/auth/fireside/mobile';
  }
  if (appId == 'fleetnow') {
    return '/api/auth/sso/fireside/mobile';
  }
  return '/auth/fireside/mobile';
}

class AppWebViewScreen extends ConsumerStatefulWidget {
  final String appId;

  const AppWebViewScreen({super.key, required this.appId});

  @override
  ConsumerState<AppWebViewScreen> createState() => _AppWebViewScreenState();
}

class _AppWebViewScreenState extends ConsumerState<AppWebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _webViewCanGoBack = false;

  @override
  void initState() {
    super.initState();
    ref.read(recentAppsProvider.notifier).record(widget.appId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final catalogue = ref.watch(catalogueProvider);
    final app = catalogue.value?.where((a) => a.id == widget.appId).firstOrNull;

    if (app == null) {
      return Scaffold(
        backgroundColor: colors.ivory,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.x),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (app.url == null) {
      return _InternalServiceView(app: app);
    }

    final health = ref.watch(healthStatusProvider(app));

    if (_controller == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _buildController(app);
      });
    }

    return PopScope(
      canPop: !_webViewCanGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleSystemBack();
      },
      child: Scaffold(
        backgroundColor: colors.ivory,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.x),
            onPressed: () => context.pop(),
            tooltip: 'Close',
          ),
          titleSpacing: 0,
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(appIconFor(app.id), color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.name,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                    StatusIndicator(
                      status: health.value ?? HealthStatus.unknown,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            _controller != null
                ? WebViewWidget(controller: _controller!)
                : const SizedBox.shrink(),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSystemBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return;
    }
    if (mounted) context.pop();
  }

  Future<void> _updateWebViewHistory() async {
    final canGoBack = await _controller?.canGoBack() ?? false;
    if (mounted && canGoBack != _webViewCanGoBack) {
      setState(() => _webViewCanGoBack = canGoBack);
    }
  }

  Future<void> _handleWebViewPermission(
    WebViewPermissionRequest request,
  ) async {
    final requestsCamera = request.types.contains(
      WebViewPermissionResourceType.camera,
    );
    final requestsMicrophone = request.types.contains(
      WebViewPermissionResourceType.microphone,
    );

    // PTW only needs the camera. Do not grant microphone access to an embedded
    // app unless that app explicitly becomes an approved use case.
    if (!requestsCamera || requestsMicrophone) {
      await request.deny();
      return;
    }

    final status = await Permission.camera.request();
    if (status.isGranted) {
      await request.grant();
    } else {
      await request.deny();
    }
  }

  Future<void> _configureAndroidWebViewPermissions(
    WebViewController controller,
  ) async {
    if (controller.platform is! AndroidWebViewController) return;

    final androidController = controller.platform as AndroidWebViewController;
    await androidController.setGeolocationEnabled(true);
    await androidController.setGeolocationPermissionsPromptCallbacks(
      onShowPrompt: (request) async {
        final status = await Permission.locationWhenInUse.request();
        return GeolocationPermissionsResponse(
          allow: status.isGranted,
          retain: status.isGranted,
        );
      },
    );
  }

  Future<void> _buildController(FiresideApplication app) async {
    final usesMobileGateway = usesMobileGatewayFor(app.id);
    final accessToken = usesMobileGateway
        ? Supabase.instance.client.auth.currentSession?.accessToken
        : null;
    final headers = accessToken == null
        ? const <String, String>{}
        : {'Authorization': 'Bearer $accessToken'};
    final controller =
        WebViewController(onPermissionRequest: _handleWebViewPermission)
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(context.appColors.ivory)
          ..addJavaScriptChannel(
            'FiresideGroupPermissions',
            onMessageReceived: (_) async {
              await openAppSettings();
            },
          )
          ..setNavigationDelegate(
            NavigationDelegate(
              onProgress: (progress) {
                if (progress >= 100) {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              onPageFinished: (url) {
                if (mounted) setState(() => _isLoading = false);
                _updateWebViewHistory();
              },
            ),
          );
    await _configureAndroidWebViewPermissions(controller);
    await controller.loadRequest(
      Uri.parse(
        usesMobileGateway
            ? '${app.url!.replaceFirst(RegExp(r'\/$'), '')}${mobileGatewayPathFor(app.id)}'
            : app.url!,
      ),
      headers: headers,
    );
    _controller = controller;
    if (mounted) setState(() {});
  }
}

class _InternalServiceView extends StatelessWidget {
  final FiresideApplication app;

  const _InternalServiceView({required this.app});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.ivory,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => context.pop(),
          tooltip: 'Close',
        ),
        title: Text(app.name),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.sand.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(LucideIcons.server, color: colors.accent, size: 34),
              ),
              const SizedBox(height: 20),
              Text(
                'Internal service',
                style: AppTypography.headlineMedium().copyWith(
                  color: colors.charcoal,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${app.name} is an internal service with no public URL. '
                'Open it over the office network or contact IT.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.muted, height: 1.4),
              ),
              if (app.repository != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    app.repository!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.charcoal,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
