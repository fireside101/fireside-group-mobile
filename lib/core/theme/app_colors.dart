import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color primary;
  final Color primaryDark;
  final Color ivory;
  final Color surface;
  final Color charcoal;
  final Color muted;
  final Color border;
  final Color sand;
  final Color accent;
  final Color statusGreen;
  final Color statusBad;
  final Color statusAmber;

  const AppColors({
    required this.primary,
    required this.primaryDark,
    required this.ivory,
    required this.surface,
    required this.charcoal,
    required this.muted,
    required this.border,
    required this.sand,
    required this.accent,
    required this.statusGreen,
    required this.statusBad,
    required this.statusAmber,
  });

  static const teal = AppColors(
    primary: Color(0xFF00BCD8),
    primaryDark: Color(0xFF0090A8),
    ivory: Color(0xFFF4FBFC),
    surface: Color(0xFFFFFFFF),
    charcoal: Color(0xFF2A2560),
    muted: Color(0xFF5B5680),
    border: Color(0xFFBDEAF3),
    sand: Color(0xFF7B6CC4),
    accent: Color(0xFF3D3587),
    statusGreen: Color(0xFF237A3B),
    statusBad: Color(0xFFB42318),
    statusAmber: Color(0xFFA15C07),
  );

  static const dark = AppColors(
    primary: Color(0xFF2A2560),
    primaryDark: Color(0xFF211D4F),
    ivory: Color(0xFF0B1220),
    surface: Color(0xFF16202E),
    charcoal: Color(0xFFE6EDF5),
    muted: Color(0xFF9AA7B8),
    border: Color(0xFF233140),
    sand: Color(0xFF2E3B4D),
    accent: Color(0xFF3D3587),
    statusGreen: Color(0xFF46C478),
    statusBad: Color(0xFFFF8A80),
    statusAmber: Color(0xFFFFC24B),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? primaryDark,
    Color? ivory,
    Color? surface,
    Color? charcoal,
    Color? muted,
    Color? border,
    Color? sand,
    Color? accent,
    Color? statusGreen,
    Color? statusBad,
    Color? statusAmber,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      ivory: ivory ?? this.ivory,
      surface: surface ?? this.surface,
      charcoal: charcoal ?? this.charcoal,
      muted: muted ?? this.muted,
      border: border ?? this.border,
      sand: sand ?? this.sand,
      accent: accent ?? this.accent,
      statusGreen: statusGreen ?? this.statusGreen,
      statusBad: statusBad ?? this.statusBad,
      statusAmber: statusAmber ?? this.statusAmber,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      ivory: Color.lerp(ivory, other.ivory, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      charcoal: Color.lerp(charcoal, other.charcoal, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      sand: Color.lerp(sand, other.sand, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      statusGreen: Color.lerp(statusGreen, other.statusGreen, t)!,
      statusBad: Color.lerp(statusBad, other.statusBad, t)!,
      statusAmber: Color.lerp(statusAmber, other.statusAmber, t)!,
    );
  }
}

extension BuildContextAppColors on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}