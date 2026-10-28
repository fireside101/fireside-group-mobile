import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/admin_audit_log_service.dart';
import '../auth/auth_controller.dart';
import '../shell/app_bottom_nav.dart';
import '../shell/app_header.dart';

/// Appearance and account preferences.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final palette = ref.watch(themePaletteProvider);
    final session = ref.watch(authControllerProvider).value;
    final canViewAdminLogs = isPortalAdmin(session?.email);

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
                  'Settings',
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                _SettingsCard(
                  icon: LucideIcons.palette,
                  title: 'Appearance',
                  child: Column(
                    children: [
                      _PaletteTile(
                        icon: LucideIcons.sun,
                        label: 'Teal (light)',
                        selected: palette == AppThemePalette.teal,
                        onTap: () => _setPalette(ref, AppThemePalette.teal),
                      ),
                      const Divider(height: 1),
                      _PaletteTile(
                        icon: LucideIcons.moon,
                        label: 'Dark',
                        selected: palette == AppThemePalette.dark,
                        onTap: () => _setPalette(ref, AppThemePalette.dark),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (canViewAdminLogs) ...[
                  _SettingsCard(
                    icon: LucideIcons.shieldCheck,
                    title: 'Administration',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        LucideIcons.fileClock,
                        color: colors.accent,
                      ),
                      title: const Text('Audit logs'),
                      subtitle: const Text(
                        'Review application access and sign-in activity',
                      ),
                      trailing: Icon(
                        LucideIcons.chevronRight,
                        color: colors.muted,
                      ),
                      onTap: () => context.push('/settings/admin-logs'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _SettingsCard(
                  icon: LucideIcons.logOut,
                  title: 'Account',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(LucideIcons.logOut, color: colors.statusBad),
                    title: Text(
                      'Sign out',
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: colors.statusBad),
                    ),
                    onTap: () => _signOut(context, ref),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }

  void _setPalette(WidgetRef ref, AppThemePalette palette) {
    ref.read(themePaletteProvider.notifier).state = palette;
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authControllerProvider.notifier).signOut();
    if (!context.mounted) return;
    context.go('/sign-in');
  }
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: selected ? colors.primary : colors.muted),
      title: Text(label),
      trailing: selected
          ? Icon(LucideIcons.check, color: colors.primary)
          : const SizedBox.shrink(),
      onTap: onTap,
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.accent, size: 18),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
