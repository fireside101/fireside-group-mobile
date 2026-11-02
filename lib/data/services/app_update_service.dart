import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateConfig {
  const AppUpdateConfig({
    this.owner = const String.fromEnvironment(
      'UPDATE_REPOSITORY_OWNER',
      defaultValue: 'fireside101',
    ),
    this.repository = const String.fromEnvironment(
      'UPDATE_REPOSITORY_NAME',
      defaultValue: 'fireside-group-mobile',
    ),
  });

  final String owner;
  final String repository;

  Uri get latestReleaseApiUri =>
      Uri.https('api.github.com', '/repos/$owner/$repository/releases/latest');

  bool isReleaseUri(Uri uri) {
    final path = uri.pathSegments;
    return uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        path.length >= 6 &&
        path[0] == owner &&
        path[1] == repository &&
        path[2] == 'releases' &&
        path[3] == 'download';
  }
}

class AppUpdateMetadata {
  const AppUpdateMetadata({
    required this.versionCode,
    required this.versionName,
    required this.releaseNotes,
    required this.apkUrl,
  });

  final int versionCode;
  final String versionName;
  final String releaseNotes;
  final Uri apkUrl;

  factory AppUpdateMetadata.fromJson(
    Map<String, dynamic> json, {
    required AppUpdateConfig config,
  }) {
    final versionCode = json['versionCode'];
    final versionName = json['versionName'];
    final releaseNotes = json['releaseNotes'];
    final apkUrlValue = json['apkUrl'];

    if (versionCode is! int || versionCode <= 0) {
      throw const FormatException('update.json has an invalid versionCode');
    }
    if (versionName is! String || versionName.trim().isEmpty) {
      throw const FormatException('update.json has an invalid versionName');
    }
    if (releaseNotes is! String) {
      throw const FormatException('update.json has invalid releaseNotes');
    }
    if (apkUrlValue is! String) {
      throw const FormatException('update.json has an invalid apkUrl');
    }

    final apkUrl = Uri.tryParse(apkUrlValue);
    if (apkUrl == null || !config.isReleaseUri(apkUrl)) {
      throw const FormatException(
        'update.json apkUrl is not a trusted release URL',
      );
    }

    return AppUpdateMetadata(
      versionCode: versionCode,
      versionName: versionName,
      releaseNotes: releaseNotes,
      apkUrl: apkUrl,
    );
  }
}

bool isNewerVersion({required int latest, required int installed}) {
  return latest > installed;
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult._({this.metadata, this.message});

  const AppUpdateCheckResult.update(AppUpdateMetadata metadata)
    : this._(metadata: metadata);

  const AppUpdateCheckResult.none() : this._();

  const AppUpdateCheckResult.unavailable(String message)
    : this._(message: message);

  final AppUpdateMetadata? metadata;
  final String? message;

  bool get hasUpdate => metadata != null;
  bool get isUnavailable => message != null;
}

class AppUpdateService {
  AppUpdateService({
    http.Client? client,
    this._packageInfo,
    this.config = const AppUpdateConfig(),
    this._androidOverride,
  }) : _client = client ?? http.Client();

  static const _timeout = Duration(seconds: 8);

  final http.Client _client;
  final PackageInfo? _packageInfo;
  final AppUpdateConfig config;
  final bool? _androidOverride;
  int? _promptedVersionCode;

  bool get _isAndroid =>
      _androidOverride ?? defaultTargetPlatform == TargetPlatform.android;

  Future<AppUpdateCheckResult> checkForUpdate() async {
    if (!_isAndroid) return const AppUpdateCheckResult.none();

    try {
      final packageInfo = _packageInfo ?? await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(packageInfo.buildNumber);
      if (installedBuild == null) {
        return const AppUpdateCheckResult.unavailable(
          'The installed build number is unavailable.',
        );
      }

      final releaseResponse = await _client
          .get(
            config.latestReleaseApiUri,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'fireside-group-mobile-updater',
            },
          )
          .timeout(_timeout);
      if (releaseResponse.statusCode == 403 ||
          releaseResponse.statusCode == 429) {
        return const AppUpdateCheckResult.unavailable(
          'GitHub update checks are temporarily rate limited.',
        );
      }
      if (releaseResponse.statusCode == 404) {
        return const AppUpdateCheckResult.unavailable(
          'No published GitHub release is available yet.',
        );
      }
      if (releaseResponse.statusCode != 200) {
        return const AppUpdateCheckResult.unavailable(
          'GitHub could not be reached right now.',
        );
      }

      final release = jsonDecode(releaseResponse.body);
      if (release is! Map<String, dynamic>) {
        return const AppUpdateCheckResult.unavailable(
          'GitHub returned malformed release data.',
        );
      }
      final assets = release['assets'];
      if (assets is! List) {
        return const AppUpdateCheckResult.unavailable(
          'The published release has no update metadata.',
        );
      }
      final metadataAsset = assets
          .cast<Object?>()
          .whereType<Map<String, dynamic>>()
          .firstWhere(
            (asset) => asset['name'] == 'update.json',
            orElse: () => <String, dynamic>{},
          );
      final metadataUrl = Uri.tryParse(
        metadataAsset['browser_download_url'] as String? ?? '',
      );
      if (metadataUrl == null || !config.isReleaseUri(metadataUrl)) {
        return const AppUpdateCheckResult.unavailable(
          'The published release has invalid update metadata.',
        );
      }

      final metadataResponse = await _client
          .get(
            metadataUrl,
            headers: const {'User-Agent': 'fireside-group-mobile-updater'},
          )
          .timeout(_timeout);
      if (metadataResponse.statusCode != 200) {
        return const AppUpdateCheckResult.unavailable(
          'The published update metadata could not be downloaded.',
        );
      }

      final decoded = jsonDecode(metadataResponse.body);
      if (decoded is! Map<String, dynamic>) {
        return const AppUpdateCheckResult.unavailable(
          'The published update metadata is malformed.',
        );
      }
      final metadata = AppUpdateMetadata.fromJson(decoded, config: config);
      if (!isNewerVersion(
        latest: metadata.versionCode,
        installed: installedBuild,
      )) {
        return const AppUpdateCheckResult.none();
      }
      return AppUpdateCheckResult.update(metadata);
    } on TimeoutException {
      return const AppUpdateCheckResult.unavailable(
        'The update check timed out. Try again later.',
      );
    } on FormatException catch (error) {
      return AppUpdateCheckResult.unavailable(error.message.toString());
    } on Object {
      return const AppUpdateCheckResult.unavailable(
        'Updates could not be checked while offline.',
      );
    }
  }

  bool shouldPrompt(AppUpdateMetadata metadata) {
    if (_promptedVersionCode == metadata.versionCode) return false;
    _promptedVersionCode = metadata.versionCode;
    return true;
  }

  Future<bool> openUpdate(AppUpdateMetadata metadata) {
    return launchUrl(metadata.apkUrl, mode: LaunchMode.externalApplication);
  }
}
