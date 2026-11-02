import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/providers.dart';
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
    final sessionName = ref.watch(authControllerProvider).value?.name;
    final profileName = ref
        .watch(profileCacheProvider)
        .value
        ?.details
        ?.editable;
    final profileFirstName = profileName?.firstName.trim() ?? '';
    final profileLastName = profileName?.lastName.trim() ?? '';
    final fallbackName = (sessionName ?? '').trim();
    final greetingName = profileFirstName.isNotEmpty
        ? [
            profileFirstName,
            profileLastName,
          ].where((part) => part.isNotEmpty).join(' ')
        : fallbackName.split(RegExp(r'\s+')).take(2).join(' ');
    final greeting = greetingName.isEmpty
        ? 'Welcome back.'
        : 'Welcome back, $greetingName.';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: colors.charcoal.withValues(alpha: 0.16),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
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
            style: AppTypography.displayMedium().copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'Launch any internal tool. Your apps are one tap away.',
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
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
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
