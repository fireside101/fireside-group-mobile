import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/providers.dart';
import '../../auth/auth_controller.dart';
import '../widgets/search_bar.dart';

/// Approved web hero (`apps/web/public/images/hero.jpeg`) as a bundled,
/// optimized 1080px WebP derivative, cover-cropped under a dark gradient so the
/// greeting and search stay readable. The brand gradient remains the fallback.
class HeroSection extends ConsumerWidget {
  static const imageAsset = 'assets/images/hero.webp';

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
    final profileName =
        ref.watch(profileCacheProvider).value?.details?.displayName.trim() ??
        '';
    final fallbackName = (sessionName ?? '').trim();
    final greetingName = profileName.isNotEmpty
        ? profileName
        : fallbackName.split(RegExp(r'\s+')).take(2).join(' ');
    final greeting = greetingName.isEmpty
        ? 'Welcome back.'
        : 'Welcome back, $greetingName.';
    // Decode no larger than the rendered width to bound image memory.
    final media = MediaQuery.of(context);
    final decodeWidth = (media.size.width * media.devicePixelRatio)
        .clamp(1, 1080)
        .round();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      clipBehavior: Clip.antiAlias,
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
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              imageAsset,
              key: const Key('hero-image'),
              fit: BoxFit.cover,
              alignment: const Alignment(0.3, -0.2),
              cacheWidth: decodeWidth,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.30),
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.78),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
            child: _content(context, greeting),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, String greeting) {
    return Column(
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
    );
  }
}
