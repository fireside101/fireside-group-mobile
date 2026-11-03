import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/providers.dart';
import 'features/settings/app_update_prompt.dart';

class FiresideGroupApp extends ConsumerStatefulWidget {
  const FiresideGroupApp({super.key});

  @override
  ConsumerState<FiresideGroupApp> createState() => _FiresideGroupAppState();
}

class _FiresideGroupAppState extends ConsumerState<FiresideGroupApp>
    with WidgetsBindingObserver {
  bool _automaticCheckInFlight = false;
  bool _updateDialogOpen = false;
  bool _automaticFailureShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runAutomaticUpdateCheck());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runAutomaticUpdateCheck());
    }
  }

  Future<void> _runAutomaticUpdateCheck({bool force = false}) async {
    if (_automaticCheckInFlight) return;
    _automaticCheckInFlight = true;
    final service = ref.read(appUpdateServiceProvider);
    try {
      final result = await service.checkForUpdate(automatic: true, force: force);
      if (!mounted) return;
      final navigatorContext = ref
          .read(routerProvider)
          .routerDelegate
          .navigatorKey
          .currentContext;
      if (navigatorContext == null || !navigatorContext.mounted) return;
      final metadata = result.metadata;
      if (metadata != null) {
        _automaticFailureShown = false;
        if (!_updateDialogOpen && service.shouldPrompt(metadata)) {
          _updateDialogOpen = true;
          await showAppUpdatePrompt(
            navigatorContext,
            metadata,
            service,
            automatic: true,
          );
          _updateDialogOpen = false;
        }
      } else if (result.isUnavailable && !_automaticFailureShown) {
        _automaticFailureShown = true;
        ScaffoldMessenger.maybeOf(navigatorContext)?.showSnackBar(
              SnackBar(
                content: Text(result.message!),
                action: SnackBarAction(
                  label: 'Retry',
                  onPressed: () => unawaited(
                    _runAutomaticUpdateCheck(force: true),
                  ),
                ),
              ),
            );
      } else if (!result.isUnavailable) {
        _automaticFailureShown = false;
      }
    } finally {
      _automaticCheckInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final palette = ref.watch(themePaletteProvider);

    return MaterialApp.router(
      title: 'Fireside Group',
      debugShowCheckedModeBanner: false,
      theme: buildTealTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: palette == AppThemePalette.teal
          ? ThemeMode.light
          : ThemeMode.dark,
      routerConfig: router,
    );
  }
}
