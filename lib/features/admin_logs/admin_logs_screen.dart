import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/admin_audit_log.dart';
import '../../data/providers.dart';
import '../shell/app_bottom_nav.dart';

class AdminLogsScreen extends ConsumerWidget {
  const AdminLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final logs = ref.watch(adminAuditLogsProvider);

    return Scaffold(
      backgroundColor: colors.ivory,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Audit logs'),
        actions: [
          IconButton(
            tooltip: 'Refresh logs',
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () => ref.invalidate(adminAuditLogsProvider),
          ),
        ],
      ),
      body: logs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load audit logs.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (items) => items.isEmpty
            ? const Center(
                child: Text('No application activity has been recorded yet.'),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(adminAuditLogsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _AuditLogCard(log: items[index]),
                ),
              ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }
}

class _AuditLogCard extends StatelessWidget {
  const _AuditLogCard({required this.log});

  final AdminAuditLog log;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final date = log.occurredAt.toLocal().toString().substring(0, 16);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.appWindow, color: colors.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  log.applicationName,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                log.success ? LucideIcons.circleCheck : LucideIcons.circleX,
                color: log.success ? colors.statusGreen : colors.statusBad,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(log.actorEmail),
          const SizedBox(height: 4),
          Text(
            '$date · ${log.eventType.replaceAll('_', ' ')}',
            style: TextStyle(color: colors.muted),
          ),
          if (log.platform != null) ...[
            const SizedBox(height: 4),
            Text(
              'Platform: ${log.platform}',
              style: TextStyle(color: colors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
