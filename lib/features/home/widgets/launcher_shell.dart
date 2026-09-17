import 'package:flutter/material.dart';

import '../../../data/models/fireside_application.dart';
import '../../app_card/app_card.dart';

/// Single-column chamfered card grid (mobile-first). Tall cards span wide on
/// desktop; on a phone everything stays one column.
class LauncherShell extends StatelessWidget {
  final List<FiresideApplication> applications;

  const LauncherShell({super.key, required this.applications});

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No applications match your search.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: _aspectRatioFor(context, constraints.maxWidth),
          ),
          itemCount: applications.length,
          itemBuilder: (context, index) {
            final app = applications[index];
            return Padding(
              padding: app.isTall
                  ? EdgeInsets.zero
                  : const EdgeInsets.only(bottom: 0),
              child: AppCard(
                application: app,
                size: app.isTall
                    ? AppCardSize.tall
                    : AppCardSize.standard,
              ),
            );
          },
        );
      },
    );
  }

  double _aspectRatioFor(BuildContext context, double width) {
    // Fixed card heights keyed to size variant; keep vertical rhythm stable.
    if (width >= 900) return 1.9;
    return 1.45;
  }
}