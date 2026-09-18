import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/fireside_application.dart';
import 'app_icon_map.dart';

/// Play Store style launcher row: app icon, name and a one-line description.
/// Tapping opens the app's detail screen (not the web app directly).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.application});

  final FiresideApplication application;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      button: true,
      label: 'Open ${application.name}',
      child: InkWell(
        onTap: () => context.push('/app/${application.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              AppIcon(application: application, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleMedium().copyWith(
                        color: colors.charcoal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      application.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall().copyWith(
                        color: colors.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      application.department.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall().copyWith(
                        color: colors.muted,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.chevronRight, color: colors.muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded app tile with the catalogue logo/icon, sized to fill [size].
class AppIcon extends StatelessWidget {
  final FiresideApplication application;
  final double size;

  const AppIcon({super.key, required this.application, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        appIconFor(application.id),
        color: Colors.white,
        size: size * 0.5,
      ),
    );
  }
}