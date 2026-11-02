import 'package:flutter/material.dart';

import '../../data/services/app_update_service.dart';

Future<void> showAppUpdatePrompt(BuildContext context, AppUpdateMetadata metadata, AppUpdateService service) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(metadata: metadata, service: service),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.metadata, required this.service});
  final AppUpdateMetadata metadata;
  final AppUpdateService service;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  UpdateProgress _progress = const UpdateProgress(UpdateState.idle);
  String? _error;
  bool _busy = false;

  Future<void> _downloadAndInstall() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.service.downloadUpdate(widget.metadata, onProgress: (progress) {
        if (mounted) setState(() => _progress = progress);
      });
      final result = await widget.service.installUpdate(widget.metadata);
      if (!mounted) return;
      if (result == UpdateInstallResult.permissionRequired) {
        setState(() { _busy = false; _progress = const UpdateProgress(UpdateState.permissionRequired); });
      } else {
        setState(() { _busy = false; _progress = const UpdateProgress(UpdateState.installing); });
      }
    } catch (error) {
      if (!mounted) return;
      final cancelled = error is UpdateCancelled;
      setState(() { _busy = false; _error = cancelled ? 'Download cancelled.' : 'Download failed. ${error.toString()}'; _progress = UpdateProgress(cancelled ? UpdateState.idle : UpdateState.failed); });
    }
  }

  Future<void> _continueAfterPermission() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await widget.service.installUpdate(widget.metadata);
      if (!mounted) return;
      if (result == UpdateInstallResult.permissionRequired) {
        setState(() { _busy = false; _error = 'Installation permission is still disabled.'; });
      } else {
        setState(() { _busy = false; _progress = const UpdateProgress(UpdateState.installing); });
      }
    } catch (error) {
      if (mounted) setState(() { _busy = false; _error = error.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fraction = _progress.fraction;
    final permission = _progress.state == UpdateState.permissionRequired;
    final installing = _progress.state == UpdateState.installing;
    return AlertDialog(
      title: Text(permission ? 'Allow installation' : 'Update available · ${widget.metadata.versionName}'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (permission) const Text('Android needs permission to install apps downloaded by Fireside Group. Enable “Allow from this source” in Settings, then return here and tap Continue installation.'),
        if (installing) const Text('Android’s package installer is open. Review its confirmation and choose Install to complete the update.'),
        if (!permission && !installing && _progress.state == UpdateState.idle) Text(widget.metadata.releaseNotes.trim().isEmpty ? 'A newer version of Fireside Group is available.' : widget.metadata.releaseNotes),
        if (fraction != null && _progress.state == UpdateState.downloading) ...[
          const SizedBox(height: 16), LinearProgressIndicator(value: fraction), const SizedBox(height: 8), Text('${(_progress.received / 1024 / 1024).toStringAsFixed(1)} MB downloaded'),
        ],
        if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
      ])),
      actions: [
        if (_progress.state == UpdateState.downloading) TextButton(onPressed: _busy ? () async { await widget.service.cancelDownload(); if (mounted) setState(() { _busy = false; _error = 'Download cancelled.'; _progress = const UpdateProgress(UpdateState.idle); }); } : null, child: const Text('Cancel')),
        if (!_busy && (installing || !permission)) TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(installing ? 'Close' : 'Later')),
        if (permission) FilledButton(onPressed: _busy ? null : _continueAfterPermission, child: const Text('Continue installation')),
        if (installing) FilledButton(onPressed: _busy ? null : _continueAfterPermission, child: const Text('Retry installation')),
        if (!permission && !installing && _progress.state != UpdateState.downloading) FilledButton(onPressed: _busy ? null : _downloadAndInstall, child: Text(_progress.state == UpdateState.failed ? 'Retry' : 'Update')),
      ],
    );
  }
}

SnackBar updateCheckSnackBar(AppUpdateCheckResult result) {
  final message = result.hasUpdate ? 'An update is available.' : result.isUnavailable ? result.message! : 'You are using the latest version.';
  return SnackBar(content: Text(message));
}
