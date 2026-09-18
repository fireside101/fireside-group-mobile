import 'dart:math';

import 'package:flutter/material.dart';

import '../../../data/models/fireside_application.dart';
import '../../app_card/app_card.dart';

/// Single-column Play Store style app rows (mobile-first). Rows spread two
/// across on desktop; on a phone everything stays one column. Rows are laid
/// out with a [Column] of [Row]s so each tile sizes to its own content instead
/// of a fixed grid height (which used to overflow).
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
        const spacing = 16.0;
        final colWidth =
            (constraints.maxWidth - 40 - spacing * (columns - 1)) / columns;

        final rows = <Widget>[];
        for (var i = 0; i < applications.length; i += columns) {
          final rowApps = applications.sublist(
            i,
            min(i + columns, applications.length),
          );
          rows.add(
            Padding(
              padding: EdgeInsets.only(
                bottom: i + columns >= applications.length ? 0 : 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < rowApps.length; j++) ...[
                    SizedBox(
                      width: colWidth,
                      child: AppCard(application: rowApps[j]),
                    ),
                    if (j < rowApps.length - 1) const SizedBox(width: spacing),
                  ],
                  if (rowApps.length < columns) const Spacer(),
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        );
      },
    );
  }
}