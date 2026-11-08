import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../data/services/session_data_cleaner.dart';
import '../../core/mobile_targets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/fireside_application.dart';
import '../../data/models/health_status.dart';
import '../../data/providers.dart';
import '../../data/services/admin_audit_log_service.dart';
import '../app_card/app_icon_map.dart';
import '../app_card/status_indicator.dart';
import 'webview_security.dart';
import 'native_camera_bridge.dart';
import 'trusted_camera_permission.dart';
import 'document_download.dart';

bool usesMobileGatewayFor(String appId) => const {
  'scorecard',
  'warehouse',
  'tadhkara',
  'bi-reporting',
  'people-directory',
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

/// PTW's existing bearer gateway redirects to root (it does not accept next).
/// Keep its identity/origin and cookie exchange, then select unified capture.
Uri? tbtLandingRedirect(String appId, String url, {MobileTargets? targets}) {
  final uri = Uri.tryParse(url);
  if (appId != 'attendance-ptw' ||
      uri == null ||
      !WebViewSecurity(appId, targets: targets).allows(url) ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.queryParameters.containsKey('source')) {
    return null;
  }
  return uri.replace(
    path: '/',
    queryParameters: {...uri.queryParameters, 'source': 'tbt'},
  );
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
  late final WebViewSecurity _security;
  StreamSubscription<AuthState>? _authSubscription;
  bool _building = false;
  static const _documentChannel = MethodChannel('fireside_group/documents');
  late final DocumentDownloadReceiver _downloads = DocumentDownloadReceiver(
    save: (bytes, name, mime) async {
      final saved = await _documentChannel.invokeMethod<bool>('saveDocument', {
        'bytes': bytes,
        'name': name,
        'mime': mime,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved == true
                  ? 'File saved.'
                  : 'Save cancelled. Your submission is unchanged.',
            ),
          ),
        );
      }
    },
  );

  void _cancelDownloads() {
    _downloads.cancel();
    unawaited(
      _documentChannel.invokeMethod<void>('cancel').catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _cancelDownloads();
    _security.close();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _security = WebViewSecurity(widget.appId);
    final account = Supabase.instance.client.auth.currentUser?.id;
    _security.accountChanged(account);
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      event,
    ) {
      if (event.event == AuthChangeEvent.initialSession ||
          (event.session?.user.id == account &&
              event.event != AuthChangeEvent.signedOut)) {
        return;
      }
      _security.accountChanged(event.session?.user.id);
      _cancelDownloads();
      _security.close();
      // The old account's cookies and web storage must not survive the switch.
      unawaited(
        clearWebViewData(controller: _controller).catchError((Object _) {}),
      );
      // Redirect rather than popping a route the auth router may have replaced.
      if (mounted) context.go('/');
    });
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

    if (_controller == null && !_building) {
      _building = true;
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
    final platform = request.platform;
    await handleTrustedCameraPermission(
      security: _security,
      sourceOrigin: platform is AndroidWebViewPermissionRequest
          ? platform.origin
          : null,
      cameraOnly:
          request.types.length == 1 &&
          request.types.contains(WebViewPermissionResourceType.camera),
      requestRuntime: () async => (await Permission.camera.request()).isGranted,
      isMounted: () => mounted,
      grant: request.grant,
      deny: request.deny,
    );
  }

  Future<void> _configureAndroidWebViewPermissions(
    WebViewController controller,
  ) async {
    if (controller.platform is! AndroidWebViewController) return;
    final android = controller.platform as AndroidWebViewController;
    await android.setGeolocationEnabled(true);
    await android.setGeolocationPermissionsPromptCallbacks(
      onShowPrompt: (request) async {
        final lease = _security.captureLease();
        if (!_security.canUseNative(sourceOrigin: request.origin)) {
          return const GeolocationPermissionsResponse(
            allow: false,
            retain: false,
          );
        }
        final status = await Permission.locationWhenInUse.request();
        return GeolocationPermissionsResponse(
          allow:
              mounted &&
              status.isGranted &&
              _security.isCurrent(lease) &&
              _security.canUseNative(sourceOrigin: request.origin),
          retain: false,
        );
      },
    );
  }

  Future<void> _handleNativeMessage(JavaScriptMessage message) async {
    if (message.message.length > 70000) return;
    try {
      final data = jsonDecode(message.message);
      if (data is! Map<String, dynamic> ||
          data['token'] is! String ||
          data['id'] is! int ||
          data['action'] is! String) {
        return;
      }
      final lease = _security.authorizeBridge(
        data['token'] as String,
        data['id'] as int,
      );
      if (lease == null || !mounted) return;
      if ((data['action'] as String).startsWith('download-')) {
        await _downloads.receive(
          data,
          () => mounted && _security.isDocumentCurrent(lease),
        );
      } else if (data['action'] == 'settings' && _security.isCurrent(lease)) {
        await openAppSettings();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Download could not be saved. Sign in and retry; files must be a supported type under 25 MB.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _buildController(FiresideApplication app) async {
    recordAppAccessInBackground(
      ref.read(adminAuditLogServiceProvider),
      applicationId: app.id,
      applicationName: app.name,
    );
    if (!mounted || !_security.allows(app.url ?? '')) {
      _building = false;
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final usesMobileGateway = usesMobileGatewayFor(app.id);
    final accessToken = usesMobileGateway
        ? Supabase.instance.client.auth.currentSession?.accessToken
        : null;
    final headers = accessToken == null
        ? const <String, String>{}
        : {'Authorization': 'Bearer $accessToken'};
    final background = context.appColors.ivory;
    final controller = WebViewController(
      onPermissionRequest: _handleWebViewPermission,
    );
    // Await security configuration before the first bearer-bearing request.
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      'FiresideNativeTransport',
      onMessageReceived: _handleNativeMessage,
    );
    await controller.setBackgroundColor(background);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (!_security.allows(request.url)) {
            return NavigationDecision.prevent;
          }
          if (request.isMainFrame) {
            _cancelDownloads();
            _security.navigationStarted();
            final landing = tbtLandingRedirect(app.id, request.url);
            if (landing != null) {
              // Cookie-only follow-up; never forward the SSO bearer again.
              unawaited(controller.loadRequest(landing));
              return NavigationDecision.prevent;
            }
          }
          return NavigationDecision.navigate;
        },
        onPageStarted: (_) {
          _cancelDownloads();
          _security.navigationStarted();
        },
        onProgress: (progress) {
          if (progress >= 100) {
            if (mounted) setState(() => _isLoading = false);
          }
        },
        onPageFinished: (url) {
          _security.pageFinished(url);

          final capability = _security.documentCapability;
          if (capability != null) {
            unawaited(
              _controller
                  ?.runJavaScript(nativeBridgeBootstrap(url, capability))
                  .catchError((Object _) {}),
            );
          }
          if (mounted) setState(() => _isLoading = false);
          _updateWebViewHistory();
        },
      ),
    );
    await _configureAndroidWebViewPermissions(controller);
    if (!mounted || !_security.allows(app.url ?? '')) return;
    _controller = controller;
    _security.navigationStarted();
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
