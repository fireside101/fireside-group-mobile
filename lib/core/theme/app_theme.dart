import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_typography.dart';

enum AppThemePalette { teal, dark }

final themePaletteProvider = StateProvider<AppThemePalette>(
  (ref) => AppThemePalette.teal,
);

ThemeData buildTealTheme() => _buildTheme(AppColors.teal);

ThemeData buildDarkTheme() => _buildTheme(AppColors.dark);

ThemeData _buildTheme(AppColors colors) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: colors.primary,
    primary: colors.textAccent,
    onPrimary: colors.ivory,
    secondary: colors.accent,
    onSecondary: Colors.white,
    surface: colors.surface,
    onSurface: colors.charcoal,
    error: colors.statusBad,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    extensions: [colors],
    scaffoldBackgroundColor: colors.ivory,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.charcoal,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppTypography.headlineMedium().copyWith(
        color: colors.charcoal,
      ),
    ),
    textTheme: AppTypography.display
        .copyWith(
          bodyLarge: AppTypography.body.bodyLarge,
          bodyMedium: AppTypography.body.bodyMedium,
          bodySmall: AppTypography.body.bodySmall,
          labelLarge: AppTypography.body.labelLarge,
          labelMedium: AppTypography.body.labelMedium,
          labelSmall: AppTypography.body.labelSmall,
          titleLarge: AppTypography.titleLarge(),
          titleMedium: AppTypography.titleMedium(),
          titleSmall: AppTypography.titleSmall(),
        )
        .apply(
          // Google Fonts ship near-black text colors; retint them so headings and
          // plain text follow the palette (light in dark mode, indigo in light).
          bodyColor: colors.charcoal,
          displayColor: colors.charcoal,
        ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.ivory,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: GoogleFonts.sourceSans3(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  );
}
