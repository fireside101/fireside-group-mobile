import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTypography {
  const AppTypography._();

  /// Fraunces for display headings. Google Fonts v6 exposes a single
  /// variable-weight static cut; we approximate the spec's 650 weight with 600.
  static TextTheme displayTextTheme() => GoogleFonts.frauncesTextTheme();

  /// Source Sans 3 for body copy.
  static TextTheme bodyTextTheme() => GoogleFonts.sourceSans3TextTheme();

  static TextTheme get display => displayTextTheme();

  static TextTheme get body => bodyTextTheme();

  static TextStyle displayLarge() => display.displayLarge ??
      GoogleFonts.fraunces(fontSize: 48, fontWeight: FontWeight.w600);

  static TextStyle displayMedium() => display.displayMedium ??
      GoogleFonts.fraunces(fontSize: 36, fontWeight: FontWeight.w600);

  static TextStyle headlineLarge() => display.headlineLarge ??
      GoogleFonts.fraunces(fontSize: 28, fontWeight: FontWeight.w600);

  static TextStyle headlineMedium() => display.headlineMedium ??
      GoogleFonts.fraunces(fontSize: 22, fontWeight: FontWeight.w600);

  static TextStyle titleLarge() => display.titleLarge ??
      GoogleFonts.fraunces(fontSize: 18, fontWeight: FontWeight.w600);

  static TextStyle bodyLarge() =>
      body.bodyLarge ?? GoogleFonts.sourceSans3(fontSize: 16);

  static TextStyle bodyMedium() =>
      body.bodyMedium ?? GoogleFonts.sourceSans3(fontSize: 14);

  static TextStyle bodySmall() =>
      body.bodySmall ?? GoogleFonts.sourceSans3(fontSize: 12);

  static TextStyle labelLarge() =>
      body.labelLarge ?? GoogleFonts.sourceSans3(fontSize: 14);

  static TextStyle labelMedium() =>
      body.labelMedium ?? GoogleFonts.sourceSans3(fontSize: 12);

  static TextStyle labelSmall() =>
      body.labelSmall ?? GoogleFonts.sourceSans3(fontSize: 11);

  static TextStyle titleMedium() =>
      body.titleMedium ?? GoogleFonts.sourceSans3(fontSize: 16);

  static TextStyle titleSmall() =>
      body.titleSmall ?? GoogleFonts.sourceSans3(fontSize: 14);
}