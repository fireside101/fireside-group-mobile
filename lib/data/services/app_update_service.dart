import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateConfig {
  const AppUpdateConfig({this.owner = const String.fromEnvironment('UPDATE_REPOSITORY_OWNER', defaultValue: 'fireside101'), this.repository = const String.fromEnvironment('UPDATE_REPOSITORY_NAME', defaultValue: 'fireside-group-mobile')});
  final String owner;
  final String repository;
  Uri get latestReleaseApiUri => Uri.https('api.github.com', '/repos/$owner/$repository/releases/latest');
  bool isReleaseUri(Uri uri) => uri.scheme == 'https' && uri.host == 'github.com' && uri.pathSegments.length >= 6 && uri.pathSegments[0] == owner && uri.pathSegments[1] == repository && uri.pathSegments[2] == 'releases' && uri.pathSegments[3] == 'download';
}

class AppUpdateMetadata {
  const AppUpdateMetadata({required this.versionCode, required this.versionName, required this.releaseNotes, required this.apkUrl, this.apkSize, this.apkSha256});
  final int versionCode;
  final String versionName;
  final String releaseNotes;
  final Uri apkUrl;
  final int? apkSize;
  final String? apkSha256;

  factory AppUpdateMetadata.fromJson(Map<String, dynamic> json, {required AppUpdateConfig config}) {
    final versionCode = json['versionCode'];
    final versionName = json['versionName'];
    final releaseNotes = json['releaseNotes'];
    final apkUrlValue = json['apkUrl'];
    if (versionCode is! int || versionCode <= 0) throw const FormatException('update.json has an invalid versionCode');
    if (versionName is! String || versionName.trim().isEmpty) throw const FormatException('update.json has an invalid versionName');
    if (releaseNotes is! String) throw const FormatException('update.json has invalid releaseNotes');
    if (apkUrlValue is! String) throw const FormatException('update.json has an invalid apkUrl');
    final apkUrl = Uri.tryParse(apkUrlValue);
    if (apkUrl == null || !config.isReleaseUri(apkUrl)) throw const FormatException('update.json apkUrl is not a trusted release URL');
    final apkSize = json['apkSize'];
    final apkSha256 = json['apkSha256'];
    if (apkSize != null && (apkSize is! int || apkSize <= 0)) throw const FormatException('update.json has an invalid apkSize');
    if (apkSha256 != null && (apkSha256 is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(apkSha256))) throw const FormatException('update.json has an invalid apkSha256');
    return AppUpdateMetadata(versionCode: versionCode, versionName: versionName, releaseNotes: releaseNotes, apkUrl: apkUrl, apkSize: apkSize as int?, apkSha256: (apkSha256 as String?)?.toLowerCase());
  }
}

bool isNewerVersion({required int latest, required int installed}) => latest > installed;

class AppUpdateCheckResult {
  const AppUpdateCheckResult._({this.metadata, this.message});
  const AppUpdateCheckResult.update(AppUpdateMetadata metadata) : this._(metadata: metadata);
  const AppUpdateCheckResult.none() : this._();
  const AppUpdateCheckResult.unavailable(String message) : this._(message: message);
  final AppUpdateMetadata? metadata;
  final String? message;
  bool get hasUpdate => metadata != null;
  bool get isUnavailable => message != null;
}

enum UpdateState { idle, downloading, ready, permissionRequired, installing, failed }

class UpdateProgress {
  const UpdateProgress(this.state, {this.received = 0, this.total, this.message});
  final UpdateState state;
  final int received;
  final int? total;
  final String? message;
  double? get fraction => total == null || total! <= 0 ? null : received / total!;
}

enum UpdateInstallResult { installerOpened, permissionRequired }

class UpdateCancelled implements Exception {
  const UpdateCancelled();
  @override
  String toString() => 'The update download was cancelled.';
}

class AppUpdateService {
  AppUpdateService({http.Client? client, this._packageInfo, this.config = const AppUpdateConfig(), this._androidOverride, this._storageDirectory, MethodChannel? platformChannel}) : _client = client ?? http.Client(), _platformChannel = platformChannel ?? const MethodChannel('fireside_group/app_updates');
  static const _timeout = Duration(seconds: 8);
  final http.Client _client;
  final PackageInfo? _packageInfo;
  final AppUpdateConfig config;
  final bool? _androidOverride;
  final Directory? _storageDirectory;
  final MethodChannel _platformChannel;
  int? _promptedVersionCode;
  StreamSubscription<List<int>>? _downloadSubscription;
  bool _downloadInProgress = false;
  bool _cancelRequested = false;
  UpdateState state = UpdateState.idle;

  bool get _isAndroid => _androidOverride ?? defaultTargetPlatform == TargetPlatform.android;

  Future<AppUpdateCheckResult> checkForUpdate() async {
    if (!_isAndroid) return const AppUpdateCheckResult.none();
    try {
      final packageInfo = _packageInfo ?? await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(packageInfo.buildNumber);
      if (installedBuild == null) return const AppUpdateCheckResult.unavailable('The installed build number is unavailable.');
      final response = await _client.get(config.latestReleaseApiUri, headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'fireside-group-mobile-updater'}).timeout(_timeout);
      if (response.statusCode == 403 || response.statusCode == 429) return const AppUpdateCheckResult.unavailable('GitHub update checks are temporarily rate limited.');
      if (response.statusCode == 404) return const AppUpdateCheckResult.unavailable('No published GitHub release is available yet.');
      if (response.statusCode != 200) return const AppUpdateCheckResult.unavailable('GitHub could not be reached right now.');
      final release = jsonDecode(response.body);
      if (release is! Map<String, dynamic> || release['assets'] is! List) return const AppUpdateCheckResult.unavailable('The published release has no update metadata.');
      final assets = (release['assets'] as List).whereType<Map<String, dynamic>>();
      final asset = assets.firstWhere((a) => a['name'] == 'update.json', orElse: () => <String, dynamic>{});
      final metadataUrl = Uri.tryParse(asset['browser_download_url'] as String? ?? '');
      if (metadataUrl == null || !config.isReleaseUri(metadataUrl)) return const AppUpdateCheckResult.unavailable('The published release has invalid update metadata.');
      final metadataResponse = await _client.get(metadataUrl, headers: const {'User-Agent': 'fireside-group-mobile-updater'}).timeout(_timeout);
      if (metadataResponse.statusCode != 200) return const AppUpdateCheckResult.unavailable('The published update metadata could not be downloaded.');
      final decoded = jsonDecode(metadataResponse.body);
      if (decoded is! Map<String, dynamic>) return const AppUpdateCheckResult.unavailable('The published update metadata is malformed.');
      final metadata = AppUpdateMetadata.fromJson(decoded, config: config);
      return isNewerVersion(latest: metadata.versionCode, installed: installedBuild) ? AppUpdateCheckResult.update(metadata) : const AppUpdateCheckResult.none();
    } on TimeoutException { return const AppUpdateCheckResult.unavailable('The update check timed out. Try again later.');
    } on FormatException catch (error) { return AppUpdateCheckResult.unavailable(error.message.toString());
    } on Object { return const AppUpdateCheckResult.unavailable('Updates could not be checked while offline.'); }
  }

  bool shouldPrompt(AppUpdateMetadata metadata) { if (_promptedVersionCode == metadata.versionCode) return false; _promptedVersionCode = metadata.versionCode; return true; }
  Future<Directory> _directory() async => _storageDirectory ?? await getApplicationSupportDirectory();
  String _fileName(AppUpdateMetadata m) => 'fireside-update-${m.versionCode}.apk';
  Future<File> _cachedFile(AppUpdateMetadata m) async => File('${(await _directory()).path}/${_fileName(m)}');

  Future<bool> _isValid(File file, AppUpdateMetadata metadata) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length <= 0 || (metadata.apkSize != null && length != metadata.apkSize)) return false;
    if (metadata.apkSha256 != null) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != metadata.apkSha256) return false;
    }
    return true;
  }

  Future<void> downloadUpdate(AppUpdateMetadata metadata, {void Function(UpdateProgress progress)? onProgress}) async {
    if (!_isAndroid) throw UnsupportedError('APK updates are only supported on Android.');
    if (_downloadInProgress) throw StateError('An update download is already in progress.');
    _downloadInProgress = true;
    _cancelRequested = false;
    state = UpdateState.downloading;
    final directory = await _directory();
    await directory.create(recursive: true);
    final target = await _cachedFile(metadata);
    if (await _isValid(target, metadata)) { state = UpdateState.ready; onProgress?.call(UpdateProgress(UpdateState.ready, received: await target.length(), total: metadata.apkSize)); _downloadInProgress = false; return; }
    final temp = File('${target.path}.part');
    try { await temp.delete(); } on FileSystemException { /* already absent */ }
    try {
      final response = await _client.send(http.Request('GET', metadata.apkUrl)).timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) throw HttpException('Download failed with HTTP ${response.statusCode}.');
      final total = metadata.apkSize ?? response.contentLength;
      var received = 0;
      final sink = temp.openWrite();
      _downloadSubscription = response.stream.listen((chunk) { received += chunk.length; sink.add(chunk); onProgress?.call(UpdateProgress(UpdateState.downloading, received: received, total: total)); });
      await _downloadSubscription!.asFuture<void>();
      await sink.close();
      if (_cancelRequested) throw const UpdateCancelled();
      if (!await _isValid(temp, metadata)) throw const FormatException('The downloaded APK failed integrity validation.');
      await temp.rename(target.path);
      state = UpdateState.ready;
      onProgress?.call(UpdateProgress(UpdateState.ready, received: received, total: total));
    } catch (error) {
      try { await temp.delete(); } on FileSystemException { /* already absent */ }
      state = UpdateState.failed;
      onProgress?.call(UpdateProgress(UpdateState.failed, message: error.toString()));
      rethrow;
    } finally { _downloadSubscription = null; _downloadInProgress = false; }
  }

  Future<void> cancelDownload() async { _cancelRequested = true; await _downloadSubscription?.cancel(); _downloadSubscription = null; }

  Future<UpdateInstallResult> installUpdate(AppUpdateMetadata metadata) async {
    final file = await _cachedFile(metadata);
    if (!await _isValid(file, metadata)) throw StateError('A complete validated APK download is required before installation.');
    final allowed = await _platformChannel.invokeMethod<bool>('canInstallPackages') ?? false;
    if (!allowed) { state = UpdateState.permissionRequired; await _platformChannel.invokeMethod<void>('openInstallPermissionSettings'); return UpdateInstallResult.permissionRequired; }
    state = UpdateState.installing;
    await _platformChannel.invokeMethod<void>('installApk', {'path': file.path});
    return UpdateInstallResult.installerOpened;
  }
}
