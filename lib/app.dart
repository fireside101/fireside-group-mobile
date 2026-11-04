import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/providers.dart';
import 'data/services/update_schedule.dart';

import 'package:flutter/foundation.dart';

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
  bool _resumed = true;
  Timer? _checkTimer;
  Timer? _downloadTimer;

  bool get _updatesEnabled =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      ref.read(updateRuntimeConfigProvider).enabled;

  Future<void> _armUpdateSchedule() async {
    if (!_updatesEnabled || !_resumed || !mounted) return;
    try {
      final delay = await ref.read(updateScheduleProvider).delayUntilDue();
      if (!mounted || !_resumed) return;
      final wakeup = ref.read(updateBackgroundWakeupProvider);
      // WorkManager is best effort, not an exact alarm. No background Auth or
      // installer is invoked until encrypted session bootstrap is implemented.
      try {
        await wakeup.register(delay.isNegative ? Duration.zero : delay);
        await wakeup.consumeReminder();
      } catch (_) {
        // Foreground deadlines remain usable without an OS scheduler.
      }
      if (!mounted || !_resumed) return;
      _checkTimer?.cancel();
      _checkTimer = Timer(
        delay.isNegative ? Duration.zero : delay,
        () => unawaited(_runAutomaticUpdateCheck()),
      );
    } catch (_) {
      // Storage failure must not become a rapid network retry loop.
      if (mounted && _resumed) {
        _checkTimer?.cancel();
        _checkTimer = Timer(
          const Duration(minutes: 15),
          () => unawaited(_armUpdateSchedule()),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_armUpdateSchedule());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkTimer?.cancel();
    _downloadTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) {
      unawaited(_armUpdateSchedule());
    } else {
      _checkTimer?.cancel();
      _downloadTimer?.cancel();
    }
  }

  Future<void> _runAutomaticUpdateCheck({bool force = false}) async {
    if (_automaticCheckInFlight || !_updatesEnabled || !_resumed) return;
    _automaticCheckInFlight = true;
    final service = ref.read(appUpdateServiceProvider);
    try {
      final result = await ref
          .read(updateScheduleProvider)
          .run(
            () => service.checkForUpdate(automatic: true, force: true),
            manual: force,
          );
      if (!mounted || !_resumed || result == null) return;
      final navigatorContext = ref
          .read(routerProvider)
          .routerDelegate
          .navigatorKey
          .currentContext;
      if (navigatorContext == null || !navigatorContext.mounted) return;
      final metadata = result.metadata;
      if (metadata != null) {
        _downloadTimer?.cancel();
        _downloadTimer = Timer(downloadJitter(manual: force), () async {
          if (!mounted ||
              !_resumed ||
              !navigatorContext.mounted ||
              _updateDialogOpen ||
              service.isDownloadInProgress ||
              !service.shouldPrompt(metadata)) {
            return;
          }
          // The existing prompt starts download immediately. Delay that entire
          // automatic path; explicit Settings checks still open it immediately.
          // Its download refreshes authorization before using an expired URL.
          _updateDialogOpen = true;
          try {
            await showAppUpdatePrompt(
              navigatorContext,
              metadata,
              service,
              automatic: true,
            );
          } finally {
            _updateDialogOpen = false;
          }
        });
        _automaticFailureShown = false;
      } else if (result.isUnavailable && !_automaticFailureShown) {
        _automaticFailureShown = true;
        ScaffoldMessenger.maybeOf(navigatorContext)?.showSnackBar(
          SnackBar(
            content: Text(result.message!),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => unawaited(_runAutomaticUpdateCheck(force: true)),
            ),
          ),
        );
      } else if (!result.isUnavailable) {
        _automaticFailureShown = false;
      }
    } catch (_) {
      // Automatic scheduling failure must never prevent the app from rendering.
    } finally {
      _automaticCheckInFlight = false;
      if (mounted && _resumed) unawaited(_armUpdateSchedule());
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
