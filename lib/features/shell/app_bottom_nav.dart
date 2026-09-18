import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nav_bar/nav_bar.dart';

import '../../core/theme/app_colors.dart';

/// Persistent glassmorphism bottom navigation. Mirrors the destinations in
/// [AppBottomNav.routes] so each screen can report the active tab index.
///
/// Uses the package's `obsidian` graph (the only style with a real
/// `BackdropFilter`) turned into a deep-blue glass pane: translucent tint,
/// high blur sigma, and no glow. The active tab's icon and label turn white;
/// inactive icons stay charcoal.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.currentIndex});

  /// Index of the currently active destination.
  final int currentIndex;

  static const List<String> routes = ['/', '/support', '/settings', '/profile'];

  static const List<(IconData, String)> _tabs = [
    (LucideIcons.home, 'Home'),
    (LucideIcons.lifeBuoy, 'Support'),
    (LucideIcons.settings, 'Settings'),
    (LucideIcons.user, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final deepBlue = colors.charcoal;
    final deepBlueAccent = colors.accent;

    return SafeArea(
      top: false,
      child: FuturisticNavBar(
      selectedIndex: currentIndex,
      onItemSelected: (index) => context.go(routes[index]),
      // Zero transition time + the bounce end-state keeps icons fixed in
      // place; only the active color changes (no pop-up / scale).
      showGlow: false,
      glowStrength: 0.0,
      animationDuration: Duration.zero,
      iconAnimationType: IconAnimationType.bounce,
      items: [
        for (var i = 0; i < _tabs.length; i++)
          NavBarItem(
            customIcon: Icon(
              _tabs[i].$1,
              color: i == currentIndex ? Colors.white : deepBlue,
              size: 24,
            ),
            customLabel: Text(
              _tabs[i].$2,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
      ],
      style: NavBarStyle.obsidian,
      blurSigma: 15.0,
      theme: FuturisticTheme(
        name: 'Fireside Glass',
        accentColor: colors.primary,
        baseColor: deepBlue,
        backgroundColor: deepBlueAccent,
        glowGradient: LinearGradient(
          colors: [colors.primaryDark, deepBlueAccent],
        ),
        particleColor: colors.primary,
        customColors: {
          'baseColor': deepBlue.withValues(alpha: 0.22),
          'baseAccentColor': deepBlueAccent.withValues(alpha: 0.16),
          'glowColor': colors.primary,
          'podShadowColor': deepBlue.withValues(alpha: 0.5),
          'podBorderColor': Colors.white.withValues(alpha: 0.18),
          'accentColor': colors.primary,
        },
      ),
    ),
  );
}
}