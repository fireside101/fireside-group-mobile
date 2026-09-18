import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/auth_controller.dart';
import '../widgets/search_bar.dart';

/// Gradient + flame-mark stand-in for the hero background image. Drop
/// `assets/images/hero_placeholder.jpg` into this `Stack` when ready.
class HeroSection extends ConsumerWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  const HeroSection({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final name = ref.watch(authControllerProvider).value?.name;
    final firstName = name?.split(' ').first;
    final greeting =
        firstName == null || firstName.isEmpty
            ? 'Welcome back.'
            : 'Welcome back, $firstName.';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryDark, colors.primary, colors.accent],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: AppTypography.displayMedium().copyWith(
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Launch any internal tool — your apps are one tap away.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
          ),
          const SizedBox(height: 24),
          AppSearchBar(
            controller: searchController,
            hint: 'Search applications',
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(LucideIcons.sparkles, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                'Fireside Africa · Internal',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}