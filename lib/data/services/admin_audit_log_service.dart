import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_audit_log.dart';

const portalAdminEmails = <String>{
  'karaba@firesidefoundation.org',
  'joseph.n@fireside.africa',
};

bool isPortalAdmin(String? email) =>
    email != null && portalAdminEmails.contains(email.trim().toLowerCase());

class AdminAuditLogService {
  AdminAuditLogService({SupabaseClient? client})
    : _client = client ?? _tryClient();

  final SupabaseClient? _client;

  Future<List<AdminAuditLog>> fetchLogs({int limit = 200}) async {
    final rows = await _requireClient()
        .from('portal_audit_logs')
        .select(
          'actor_email, application_name, event_type, success, '
          'occurred_at, platform',
        )
        .order('occurred_at', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(AdminAuditLog.fromJson)
        .toList(growable: false);
  }

  Future<void> recordAppAccess({
    required String applicationId,
    required String applicationName,
  }) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null || user.email == null) return;

    try {
      await client.from('portal_audit_logs').insert({
        'actor_id': user.id,
        'actor_email': user.email!.trim().toLowerCase(),
        'application_id': applicationId,
        'application_name': applicationName,
        'event_type': 'app_open_requested',
        'success': true,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      });
    } catch (_) {
      // Logging must never prevent a user from opening an application.
    }
  }

  SupabaseClient _requireClient() =>
      _client ?? (throw StateError('Supabase is not configured.'));

  static SupabaseClient? _tryClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}

void recordAppAccessInBackground(
  AdminAuditLogService service, {
  required String applicationId,
  required String applicationName,
}) {
  unawaited(
    service.recordAppAccess(
      applicationId: applicationId,
      applicationName: applicationName,
    ),
  );
}
