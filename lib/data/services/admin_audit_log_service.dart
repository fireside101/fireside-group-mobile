import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const _queueKey = 'portal_audit_log_queue_v1';
  static const _batchSize = 25;
  static const _maxQueueSize = 500;
  Future<void> _queueOperation = Future<void>.value();

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
  }) {
    // Serialize queue reads/writes so rapid app opens cannot overwrite one
    // another in SharedPreferences.
    _queueOperation = _queueOperation.then(
      (_) => _enqueueAndFlush(
        applicationId: applicationId,
        applicationName: applicationName,
      ),
    );
    return _queueOperation;
  }

  Future<void> _enqueueAndFlush({
    required String applicationId,
    required String applicationName,
  }) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null || user.email == null) return;

    try {
      final preferences = await SharedPreferences.getInstance();
      final queue = _readQueue(preferences);
      queue.add({
        'actor_id': user.id,
        'actor_email': user.email!.trim().toLowerCase(),
        'application_id': applicationId,
        'application_name': applicationName,
        'event_type': 'app_open_requested',
        'success': true,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      });

      final boundedQueue = queue.length > _maxQueueSize
          ? queue.sublist(queue.length - _maxQueueSize)
          : queue;
      await _writeQueue(preferences, boundedQueue);
      await _flushBatch(preferences, user.id);
    } catch (_) {
      // Queueing and uploading must never block application access.
    }
  }

  Future<void> _flushBatch(SharedPreferences preferences, String userId) async {
    final client = _client;
    if (client == null) return;

    final queue = _readQueue(preferences);
    final batch = queue
        .where((entry) => entry['actor_id'] == userId)
        .take(_batchSize)
        .toList(growable: false);
    if (batch.isEmpty) return;

    try {
      await client.from('portal_audit_logs').insert(batch);
      final uploaded = queue
          .where((entry) => !batch.contains(entry))
          .toList(growable: false);
      await _writeQueue(preferences, uploaded);
    } catch (_) {
      // Keep the batch for the next app open if the request fails.
    }
  }

  List<Map<String, dynamic>> _readQueue(SharedPreferences preferences) {
    final raw = preferences.getString(_queueKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _writeQueue(
    SharedPreferences preferences,
    List<Map<String, dynamic>> queue,
  ) async {
    await preferences.setString(_queueKey, jsonEncode(queue));
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
