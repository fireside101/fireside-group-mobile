import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/fireside_application.dart';
import '../../data/models/health_status.dart';
import '../../data/providers.dart';
import '../app_card/app_card.dart';
import '../app_card/status_indicator.dart';

/// Play Store style app detail: big icon, name, health + an Install action,
/// the full description and a details list. Once installed the action becomes
/// an inactive "Already installed" button.
class AppDetailScreen extends ConsumerStatefulWidget {
  final String appId;

  const AppDetailScreen({super.key, required this.appId});

  @override
  ConsumerState<AppDetailScreen> createState() => _AppDetailScreenState();
}

class _AppDetailScreenState extends ConsumerState<AppDetailScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(recentAppsProvider.notifier).record(widget.appId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final catalogue = ref.watch(catalogueProvider);
    final app = catalogue.value
        ?.where((a) => a.id == widget.appId)
        .firstOrNull;

    if (app == null) {
      return Scaffold(
        backgroundColor: colors.ivory,
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final health = ref.watch(healthStatusProvider(app));
    final status = health.value ?? HealthStatus.unknown;

    return Scaffold(
      backgroundColor: colors.ivory,
      appBar: AppBar(
        title: Text(
          app.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Row(
            children: [
              AppIcon(application: app, size: 96),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.name,
                      style: AppTypography.headlineMedium().copyWith(
                        color: colors.charcoal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      app.department,
                      style: AppTypography.bodyMedium().copyWith(
                        color: colors.muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    StatusIndicator(status: status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _InstallButton(application: app),
          const SizedBox(height: 28),
          Text(
            'About this app',
            style: AppTypography.titleLarge().copyWith(
              color: colors.charcoal,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            app.description,
            style: AppTypography.bodyLarge().copyWith(
              color: colors.charcoal,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Details',
            style: AppTypography.titleLarge().copyWith(
              color: colors.charcoal,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _DetailsList(application: app),
        ],
      ),
    );
  }
}

class _InstallButton extends ConsumerWidget {
  const _InstallButton({required this.application});

  final FiresideApplication application;

  Future<void> _install(BuildContext context, WidgetRef ref) async {
    await ref.read(installedAppsProvider.notifier).install(application.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${application.name} has been installed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(installedAppsProvider);
    final isInstalled = installed.value?.contains(application.id) ?? false;
    final isLoading = installed.isLoading;

    return SizedBox(
      height: 52,
      width: double.infinity,
      child: isInstalled
          ? FilledButton.tonalIcon(
              onPressed: null,
              icon: const Icon(LucideIcons.check, size: 20),
              label: const Text(
                'Already installed',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            )
          : FilledButton.icon(
              onPressed: isLoading
                  ? null
                  : () => _install(context, ref),
              icon: const Icon(LucideIcons.download, size: 20),
              label: const Text(
                'Install',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
    );
  }
}

class _DetailsList extends StatelessWidget {
  const _DetailsList({required this.application});

  final FiresideApplication application;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final rows = <(IconData, String, String)>[
      (LucideIcons.building2, 'Department', application.department),
      (
        LucideIcons.tag,
        'Category',
        application.category.isEmpty
            ? '—'
            : application.category[0].toUpperCase() +
                application.category.substring(1),
      ),
      (LucideIcons.server, 'Access', application.repository ?? 'Web app'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          for (final (icon, label, value) in rows)
            _DetailRow(icon: icon, label: label, value: value),
          if (application.keywords.isNotEmpty)
            _KeywordRow(keywords: application.keywords),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: colors.accent, size: 18),
          const SizedBox(width: 12),
          Text(
            label,
            style: AppTypography.bodySmall().copyWith(
              color: colors.muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium().copyWith(
                color: colors.charcoal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeywordRow extends StatelessWidget {
  const _KeywordRow({required this.keywords});

  final List<String> keywords;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final keyword in keywords)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.sand.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                keyword,
                style: AppTypography.labelSmall().copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}