import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../auth/auth_controller.dart';

/// Sticky top bar with brand, nav links, and the signed-in user's avatar.
class AppHeader extends ConsumerWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;

    return Material(
      color: colors.surface,
      elevation: 0.5,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border, width: 0.5)),
        ),
        child: Row(
          children: [
            InkWell(
              onTap: () => context.go('/'),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(LucideIcons.flame, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Fireside',
                    style: AppTypography.titleLarge().copyWith(
                      color: colors.charcoal,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Open navigation',
              icon: Icon(LucideIcons.menu, color: colors.charcoal),
              onPressed: () => _showDrawer(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _showDrawer(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Consumer(
          builder: (context, ref, _) {
            final colors = context.appColors;
            final session = ref.watch(authControllerProvider).value;
            final nav = <(IconData, String, String)>[
              (LucideIcons.home, 'Home', '/'),
              (LucideIcons.layoutGrid, 'All applications', '/applications'),
            ];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage:
                            session?.photoUrl != null ? NetworkImage(session!.photoUrl!) : null,
                        backgroundColor: colors.accent,
                        child: session?.photoUrl == null
                            ? Text(
                                session?.name.characters.first.toUpperCase() ?? '?',
                                style: const TextStyle(color: Colors.white),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session?.name ?? 'Guest',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            Text(
                              session?.email ?? 'Sign in to continue',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.muted,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                for (final (icon, label, route) in nav)
                  ListTile(
                    leading: Icon(icon, color: colors.charcoal),
                    title: Text(label),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.go(route);
                    },
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(LucideIcons.logOut,
                      color: session == null ? colors.muted : colors.statusBad),
                  title: Text(session == null ? 'Sign in' : 'Sign out'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    if (session == null) {
                      context.go('/sign-in');
                    } else {
                      ref.read(authControllerProvider.notifier).signOut();
                      context.go('/sign-in');
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
  }
}