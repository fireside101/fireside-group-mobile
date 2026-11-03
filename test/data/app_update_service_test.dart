import 'dart:async';
import 'dart:convert';

import 'package:fireside_group/data/services/app_update_service.dart';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _config = AppUpdateConfig(
  owner: 'fireside101',
  repository: 'fireside-group-mobile',
);

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('fireside-update-test-');
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  group('isNewerVersion', () {
    test('compares numeric build numbers', () {
      expect(isNewerVersion(latest: 12, installed: 11), isTrue);
      expect(isNewerVersion(latest: 11, installed: 11), isFalse);
      expect(isNewerVersion(latest: 10, installed: 11), isFalse);
    });
  });

  group('AppUpdateMetadata', () {
    test('parses valid release metadata', () {
      final metadata = AppUpdateMetadata.fromJson({
        'versionCode': 12,
        'versionName': '1.0.1',
        'releaseNotes': 'Fixes and improvements',
        'apkUrl': 'https://github.com/fireside101/fireside-group-mobile/releases/download/v1.0.1/fireside-group-v1.0.1.apk',
      }, config: _config);

      expect(metadata.versionCode, 12);
      expect(metadata.versionName, '1.0.1');
      expect(metadata.releaseNotes, 'Fixes and improvements');
    });

    test('rejects an APK URL outside the configured release repository', () {
      expect(
        () => AppUpdateMetadata.fromJson({
          'versionCode': 12,
          'versionName': '1.0.1',
          'releaseNotes': 'Fixes and improvements',
          'apkUrl': 'https://example.com/fireside-group.apk',
        }, config: _config),
        throwsFormatException,
      );
    });

    test('rejects malformed version metadata', () {
      expect(
        () => AppUpdateMetadata.fromJson({
          'versionCode': '12',
          'versionName': '1.0.1',
          'releaseNotes': 'Fixes and improvements',
          'apkUrl': 'https://github.com/fireside101/fireside-group-mobile/releases/download/v1.0.1/fireside-group-v1.0.1.apk',
        }, config: _config),
        throwsFormatException,
      );
    });

    test('accepts older metadata without integrity fields', () {
      final metadata = AppUpdateMetadata.fromJson({
        'versionCode': 12,
        'versionName': '1.0.1',
        'releaseNotes': '',
        'apkUrl': 'https://github.com/fireside101/fireside-group-mobile/releases/download/v1.0.1/app.apk',
      }, config: _config);
      expect(metadata.apkSize, isNull);
      expect(metadata.apkSha256, isNull);
    });
  });

  final metadata = AppUpdateMetadata(
    versionCode: 12,
    versionName: '1.0.1',
    releaseNotes: 'Notes',
    apkUrl: Uri.parse('https://github.com/fireside101/fireside-group-mobile/releases/download/v1.0.1/app.apk'),
    apkSize: 4,
  );

  test('rejects failed downloads and leaves no installable file', () async {
    final client = _ResponseClient((_) => http.StreamedResponse(const Stream<List<int>>.empty(), 503));
    final service = AppUpdateService(client: client, androidOverride: true, storageDirectory: tempDirectory);
    await expectLater(service.downloadUpdate(metadata), throwsA(isA<HttpException>()));
    expect(await File('${tempDirectory.path}/fireside-update-12.apk').exists(), isFalse);
    expect(await File('${tempDirectory.path}/fireside-update-12.apk.part').exists(), isFalse);
    expect(service.state, UpdateState.failed);
  });

  test('does not retain an incomplete or invalid download', () async {
    final client = _ResponseClient((_) => http.StreamedResponse(Stream.value([1, 2, 3]), 200, contentLength: 3));
    final service = AppUpdateService(client: client, androidOverride: true, storageDirectory: tempDirectory);
    await expectLater(service.downloadUpdate(metadata), throwsA(isA<FormatException>()));
    expect(await File('${tempDirectory.path}/fireside-update-12.apk').exists(), isFalse);
    expect(await File('${tempDirectory.path}/fireside-update-12.apk.part').exists(), isFalse);
  });

  test('reuses a validated cached APK without a second request', () async {
    var requests = 0;
    final client = _ResponseClient((_) {
      requests++;
      return http.StreamedResponse(Stream.value([1, 2, 3, 4]), 200, contentLength: 4);
    });
    final service = AppUpdateService(client: client, androidOverride: true, storageDirectory: tempDirectory);
    await service.downloadUpdate(metadata);
    await service.downloadUpdate(metadata);
    expect(requests, 1);
    expect(service.state, UpdateState.ready);
  });

  test('prevents duplicate simultaneous downloads', () async {
    final client = _ResponseClient((_) => asyncResponse());
    final service = AppUpdateService(client: client, androidOverride: true, storageDirectory: tempDirectory);
    final first = service.downloadUpdate(metadata);
    await expectLater(service.downloadUpdate(metadata), throwsA(isA<StateError>()));
    await first;
  });

  test('manual checks can reopen a deferred update', () {
    final service = AppUpdateService(
      androidOverride: true,
      storageDirectory: tempDirectory,
    );
    service.deferUpdate(metadata);
    expect(service.shouldPrompt(metadata), isFalse);
    expect(service.shouldPrompt(metadata, manual: true), isTrue);
  });

  test('automatic checks are cooled down and do not overlap', () async {
    var requests = 0;
    final client = _ResponseClient((request) {
      requests++;
      if (request.url.path.endsWith('/releases/latest')) {
        return http.Response(
          '{"assets":[{"name":"update.json","browser_download_url":"https://github.com/fireside101/fireside-group-mobile/releases/download/v1.0.4/update.json"}]}',
          200,
        ).toStreamed();
      }
      return http.Response(
        '{"versionCode":5,"versionName":"1.0.4","releaseNotes":"","apkUrl":"https://github.com/fireside101/fireside-group-mobile/releases/download/v1.0.4/app.apk"}',
        200,
      ).toStreamed();
    });
    final service = AppUpdateService(
      client: client,
      packageInfo: PackageInfo(
        appName: 'Fireside',
        packageName: 'com.firesideafrica.firesidegroup',
        version: '1.0.3',
        buildNumber: '4',
      ),
      androidOverride: true,
      storageDirectory: tempDirectory,
    );
    final first = service.checkForUpdate(automatic: true);
    final second = service.checkForUpdate(automatic: true);
    final results = await Future.wait([first, second]);
    expect(results.every((result) => result.hasUpdate), isTrue);
    expect(requests, 2);
    await service.checkForUpdate(automatic: true);
    expect(requests, 2);
  });

  test('cancellation completes and permits a retry', () async {
    final streamController = StreamController<List<int>>();
    var requests = 0;
    final client = _ResponseClient((_) {
      requests++;
      if (requests == 1) return http.StreamedResponse(streamController.stream, 200);
      return http.StreamedResponse(Stream.value([1, 2, 3, 4]), 200, contentLength: 4);
    });
    final service = AppUpdateService(
      client: client,
      androidOverride: true,
      storageDirectory: tempDirectory,
    );
    final pending = service.downloadUpdate(metadata);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final cancellation = expectLater(pending, throwsA(isA<UpdateCancelled>()));
    await service.cancelDownload();
    await cancellation;
    expect(service.isDownloadInProgress, isFalse);
    await service.downloadUpdate(metadata);
    expect(service.state, UpdateState.ready);
  });
}

http.StreamedResponse asyncResponse() => http.StreamedResponse(Stream.value([1, 2, 3, 4]), 200, contentLength: 4);

extension on http.Response {
  http.StreamedResponse toStreamed() => http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    headers: headers,
    reasonPhrase: reasonPhrase,
    contentLength: bodyBytes.length,
  );
}

class _ResponseClient extends http.BaseClient {
  _ResponseClient(this.handler);
  final http.StreamedResponse Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => handler(request);
}
