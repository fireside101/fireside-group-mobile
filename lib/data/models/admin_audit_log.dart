class AdminAuditLog {
  const AdminAuditLog({
    required this.actorEmail,
    required this.applicationName,
    required this.eventType,
    required this.success,
    required this.occurredAt,
    this.platform,
  });

  final String actorEmail;
  final String applicationName;
  final String eventType;
  final bool success;
  final DateTime occurredAt;
  final String? platform;

  factory AdminAuditLog.fromJson(Map<String, dynamic> json) {
    return AdminAuditLog(
      actorEmail: json['actor_email'] as String? ?? 'Unknown user',
      applicationName: json['application_name'] as String? ?? 'Unknown app',
      eventType: json['event_type'] as String? ?? 'unknown',
      success: json['success'] as bool? ?? false,
      occurredAt:
          DateTime.tryParse(json['occurred_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      platform: json['platform'] as String?,
    );
  }
}
