import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shapes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/fireside_application.dart';
import '../../data/models/health_status.dart';
import '../../data/providers.dart';
import 'app_icon_map.dart';
import 'status_indicator.dart';

enum AppCardSize { standard, tall, compact }

class AppCard extends ConsumerWidget {
  final FiresideApplication application;
  final AppCardSize size;

  const AppCard({
    super.key,
    required this.application,
    this.size = AppCardSize.standard,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthStatusProvider(application));

    return Semantics(
      button: true,
      label: 'Open ${application.name}',
      child: InkWell(
        onTap: () => context.push('/app/${application.id}'),
        borderRadius: BorderRadius.circular(kCardRadius),
        child: switch (size) {
          AppCardSize.standard => _StandardCard(
              application: application,
              health: health,
            ),
          AppCardSize.tall => _TallCard(
              application: application,
              health: health,
            ),
          AppCardSize.compact => _CompactCard(application: application),
        },
      ),
    );
  }
}

class _CardFrame extends StatelessWidget {
  final Widget child;

  const _CardFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ChamferedCard(
      color: colors.surface,
      borderColor: colors.border,
      borderWidth: 1,
      child: child,
    );
  }
}

class _AppIcon extends StatelessWidget {
  final FiresideApplication application;
  final double size;

  const _AppIcon({required this.application, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(appIconFor(application.id), color: Colors.white, size: size * 0.5),
    );
  }
}

class _CardContent extends StatelessWidget {
  final FiresideApplication application;
  final AsyncValue<HealthStatus> health;
  final bool tall;

  const _CardContent({
    required this.application,
    required this.health,
    this.tall = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final status = health.value ?? HealthStatus.unknown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    application.department.toUpperCase(),
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.muted,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: tall ? 14 : 8),
                  Text(
                    application.name,
                    style: AppTypography.titleLarge().copyWith(
                      color: colors.charcoal,
                      fontSize: tall ? 26 : 20,
                    ),
                  ),
                  if (tall) const SizedBox(height: 8),
                  if (tall)
                    Text(
                      application.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(color: colors.muted),
                    ),
                ],
              ),
            ),
            _AppIcon(application: application, size: tall ? 52 : 44),
          ],
        ),
        if (!tall) const SizedBox(height: 12),
        if (!tall)
          Text(
            application.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(color: colors.muted),
          ),
        const Spacer(),
        Row(
          children: [
            if (health.isLoading && status == HealthStatus.unknown)
              const SmallProgress()
            else
              StatusIndicator(status: status),
            const Spacer(),
            _OpenButton(hasUrl: application.url != null),
          ],
        ),
      ],
    );
  }
}

class _OpenButton extends StatelessWidget {
  final bool hasUrl;

  const _OpenButton({required this.hasUrl});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasUrl ? 'Open' : 'Internal',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.ivory,
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (hasUrl) ...[
            const SizedBox(width: 4),
            Icon(LucideIcons.arrowUpRight, color: colors.ivory, size: 14),
          ],
        ],
      ),
    );
  }
}

class _StandardCard extends StatelessWidget {
  final FiresideApplication application;
  final AsyncValue<HealthStatus> health;

  const _StandardCard({required this.application, required this.health});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: _CardFrame(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: _CardContent(application: application, health: health),
        ),
      ),
    );
  }
}

class _TallCard extends StatelessWidget {
  final FiresideApplication application;
  final AsyncValue<HealthStatus> health;

  const _TallCard({required this.application, required this.health});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: _CardFrame(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _CardContent(application: application, health: health, tall: true),
        ),
      ),
    );
  }
}

class _CompactCard extends StatelessWidget {
  final FiresideApplication application;

  const _CompactCard({required this.application});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    return _CardFrame(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _AppIcon(application: application, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    application.department.toUpperCase(),
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.muted,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    application.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleLarge().copyWith(
                      color: colors.charcoal,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: colors.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

class SmallProgress extends StatelessWidget {
  const SmallProgress({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: 10,
      height: 10,
      child: CircularProgressIndicator(strokeWidth: 1.6, color: colors.muted),
    );
  }
}