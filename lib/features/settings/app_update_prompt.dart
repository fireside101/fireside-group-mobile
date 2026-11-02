import 'package:flutter/material.dart';

import '../../data/services/app_update_service.dart';

Future<void> showAppUpdatePrompt(
  BuildContext context,
  AppUpdateMetadata metadata,
  AppUpdateService service,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Update available · ${metadata.versionName}'),
      content: SingleChildScrollView(
        child: Text(
          metadata.releaseNotes.trim().isEmpty
              ? 'A newer version of Fireside Group is available.'
              : metadata.releaseNotes,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await service.openUpdate(metadata);
          },
          child: const Text('Update'),
        ),
      ],
    ),
  );
}

SnackBar updateCheckSnackBar(AppUpdateCheckResult result) {
  final message = result.hasUpdate
      ? 'An update is available.'
      : result.isUnavailable
      ? result.message!
      : 'You are using the latest version.';
  return SnackBar(content: Text(message));
}
