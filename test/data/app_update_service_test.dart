import 'package:fireside_group/data/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _config = AppUpdateConfig(
  owner: 'fireside101',
  repository: 'fireside-group-mobile',
);

void main() {
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
  });
}
