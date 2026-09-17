import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';

/// Help/contact block. Replace `mailto:` with the real internal address.
class SupportSection extends StatelessWidget {
  const SupportSection({super.key});

  static const _supportEmail = 'support@fireside.africa';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.sand.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.lifeBuoy, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need help?',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Contact the IT team for access or issues.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.muted,
                      ),
                ),
              ],
            ),
          ),
          IconButton.outlined(
            tooltip: 'Email support',
            icon: Icon(LucideIcons.mail, color: colors.accent),
            onPressed: () => _emailSupport(),
          ),
        ],
      ),
    );
  }

  Future<void> _emailSupport() async {
    final uri = Uri(scheme: 'mailto', path: _supportEmail);
    final launched = await launchUrl(uri);
    if (!launched) {
      debugPrint('Could not open mailto: $_supportEmail');
    }
  }
}