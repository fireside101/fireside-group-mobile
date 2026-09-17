enum HealthStatus { available, unavailable, unknown }

extension HealthStatusLabel on HealthStatus {
  String get label => switch (this) {
        HealthStatus.available => 'Available',
        HealthStatus.unavailable => 'Unavailable',
        HealthStatus.unknown => 'Unknown',
      };
}