import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Maps each catalogue app id to a lucide icon, mirroring the web app's
/// per-app iconography on the launcher cards.
IconData appIconFor(String appId) => switch (appId) {
  'warehouse' => LucideIcons.warehouse,
  'scorecard' => LucideIcons.clipboardCheck,
  'operations-scoreboard' => LucideIcons.gauge,
  'tadhkara' => LucideIcons.heartHandshake,
  'planning-tracker' => LucideIcons.calendarRange,
  'people-directory' => LucideIcons.users,
  'bi-reporting' => LucideIcons.barChart3,
  'attendance-ptw' => LucideIcons.calendarCheck,
  'maintenance-tracker' => LucideIcons.wrench,
  'fleetnow' => LucideIcons.truck,
  'ict-support' => LucideIcons.headphones,
  'fuel-control-system' => LucideIcons.fuel,
  _ => LucideIcons.box,
};
