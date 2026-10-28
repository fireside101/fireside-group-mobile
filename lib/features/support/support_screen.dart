import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../home/widgets/support_section.dart';
import '../shell/app_bottom_nav.dart';
import '../shell/app_header.dart';

/// Support hub — help and contact options for IT issues.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.ivory,
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Text(
                  'Support',
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Find answers and reach the team when something is not working.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.muted),
                ),
                const SizedBox(height: 20),
                const SupportSection(),
                const SizedBox(height: 12),
                const _SupportCard(
                  icon: LucideIcons.clock,
                  title: 'Business hours',
                  body: 'Monday to Friday, 08:00 – 17:00 EAT. Saturday, 08:00 – 13:00 EAT.',
                ),
                const SizedBox(height: 12),
                const _SupportCard(
                  icon: LucideIcons.timer,
                  title: 'Response time',
                  body: 'Support requests are answered within an hour.',
                ),
                const SizedBox(height: 12),
                const _SupportCard(
                  icon: LucideIcons.fileQuestion,
                  title: 'Frequently asked questions',
                  body: 'Access and permissions are managed by the IT team.',
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.sand.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: colors.accent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
