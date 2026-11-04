import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';

/// Two quiet presentations of the same cached, installed package metadata.
class InstalledVersionLabel extends ConsumerWidget {
  const InstalledVersionLabel({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(installedPackageInfoProvider);
    return packageInfo.when(
      loading: () => compact
          ? const SizedBox.shrink()
          : const Text('Loading installed version…'),
      error: (_, _) =>
          compact ? const SizedBox.shrink() : const Text('Version unavailable'),
      data: (info) {
        final version = info.version.trim();
        final build = info.buildNumber.trim();
        final versionLabel = version.isEmpty
            ? 'Version unavailable'
            : 'Version $version';
        final label = build.isEmpty
            ? '$versionLabel (build unavailable)'
            : '$versionLabel (build $build)';
        if (!compact) return Text(label);
        if (version.isEmpty) return const SizedBox.shrink();
        final colors = context.appColors;
        return Tooltip(
          message: label,
          child: Text(
            'v$version',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colors.muted),
          ),
        );
      },
    );
  }
}
