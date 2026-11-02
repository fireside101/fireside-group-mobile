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

class _FiresideGroupAppState extends ConsumerState<FiresideGroupApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForStartupUpdate());
    });
  }

  Future<void> _checkForStartupUpdate() async {
    final service = ref.read(appUpdateServiceProvider);
    final result = await service.checkForUpdate();
    final metadata = result.metadata;
    if (!mounted || metadata == null) return;

    final navigatorContext = ref
        .read(routerProvider)
        .routerDelegate
        .navigatorKey
        .currentContext;
    if (navigatorContext == null || !navigatorContext.mounted) return;
    if (!service.shouldPrompt(metadata)) return;
    await showAppUpdatePrompt(navigatorContext, metadata, service);
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
