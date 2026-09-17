import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

enum AppThemePalette { teal, red }

final themePaletteProvider =
    StateProvider<AppThemePalette>((ref) => AppThemePalette.teal);

class FiresideGroupApp extends ConsumerWidget {
  const FiresideGroupApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final palette = ref.watch(themePaletteProvider);

    return MaterialApp.router(
      title: 'Fireside Group',
      debugShowCheckedModeBanner: false,
      theme: buildTealTheme(),
      darkTheme: buildRedTheme(),
      themeMode: palette == AppThemePalette.teal
          ? ThemeMode.light
          : ThemeMode.dark,
      routerConfig: router,
    );
  }
}