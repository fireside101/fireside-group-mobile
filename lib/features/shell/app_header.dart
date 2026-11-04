import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/providers.dart';
import '../auth/auth_controller.dart';
import 'installed_version_label.dart';

/// Sticky top bar with the brand mark and home link.
class AppHeader extends ConsumerStatefulWidget {
  const AppHeader({super.key});

  @override
  ConsumerState<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends ConsumerState<AppHeader> {
  @override
  void initState() {
    super.initState();
    ref.read(profileCacheProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final session = ref.watch(authControllerProvider).value;
    final cachedProfile = ref.watch(profileCacheProvider).value;
    final profileName = cachedProfile?.details?.displayName.trim() ?? '';
    final name = profileName.isNotEmpty
        ? profileName
        : session?.name.trim().isNotEmpty == true
        ? session!.name.trim()
        : 'Fireside user';
    final initial = name.characters.first.toUpperCase();
    final photoUrl = cachedProfile?.avatarUrl.isNotEmpty == true
        ? cachedProfile!.avatarUrl
        : session?.photoUrl;

    return Material(
      color: colors.surface,
      elevation: 0.5,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border, width: 0.5)),
        ),
        child: SafeArea(
          bottom: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => context.go('/'),
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fireside Group',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleLarge().copyWith(
                              color: colors.charcoal,
                            ),
                          ),
                          const InstalledVersionLabel(compact: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label: 'Open profile',
                    child: InkWell(
                      onTap: () => context.go('/profile'),
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: colors.primary,
                          child: photoUrl == null || photoUrl.isEmpty
                              ? Text(
                                  initial,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : ClipOval(
                                  child: Image.network(
                                    photoUrl,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Center(
                                      child: Text(
                                        initial,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
