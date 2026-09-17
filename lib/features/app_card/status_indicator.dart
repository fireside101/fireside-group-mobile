import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/health_status.dart';

class StatusIndicator extends StatelessWidget {
  final HealthStatus status;
  final bool compact;

  const StatusIndicator({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = switch (status) {
      HealthStatus.available => colors.statusGreen,
      HealthStatus.unavailable => colors.statusBad,
      HealthStatus.unknown => colors.statusAmber,
    };

    final label = status.label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 6 : 8,
          height: compact ? 6 : 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: compact ? 4 : 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}