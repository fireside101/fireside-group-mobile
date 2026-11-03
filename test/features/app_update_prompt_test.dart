import 'dart:async';
import 'dart:io';

import 'package:fireside_group/data/services/app_update_service.dart';
import 'package:fireside_group/features/settings/app_update_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _ApkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value([1, 2, 3, 4]),
      200,
      contentLength: 4,
    );
  }
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fireside-update-dialog-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  testWidgets('automatically downloads when an update dialog opens', (tester) async {
    final metadata = AppUpdateMetadata(
      versionCode: 5,
      versionName: '1.0.4',
      releaseNotes: 'Improvements',
      apkUrl: Uri.parse('https://github.com/fireside101/fireside-group-mobile/releases/download/v1.0.4/app.apk'),
      apkSize: 4,
    );
    final service = AppUpdateService(
      client: _ApkClient(),
      androidOverride: true,
      storageDirectory: directory,
    );

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    unawaited(showAppUpdatePrompt(
      tester.element(find.byType(SizedBox)),
      metadata,
      service,
      automatic: true,
    ));
    await tester.pump();
    for (var index = 0; index < 10; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(service.isDownloadInProgress, isTrue);
    await tester.runAsync(service.cancelDownload);
    await tester.pumpAndSettle();
  });
}
