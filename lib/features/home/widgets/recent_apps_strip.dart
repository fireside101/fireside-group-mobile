import 'package:flutter/material.dart';

import '../../../data/models/fireside_application.dart';
import '../../app_card/app_card.dart';

/// Horizontal strip of recently opened apps (most recent first).
/// Rendered only when non-empty by the caller.
class RecentAppsStrip extends StatelessWidget {
  final List<FiresideApplication> applications;

  const RecentAppsStrip({super.key, required this.applications});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Text(
            'Recent',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: applications.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return SizedBox(
                width: 260,
                child: AppCard(
                  application: applications[index],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}