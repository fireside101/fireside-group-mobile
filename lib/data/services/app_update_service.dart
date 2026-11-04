import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'update_registry.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateConfig {
  const AppUpdateConfig({this.storageBase = const String.fromEnvironment('UPDATE_STORAGE_BASE'), this.owner = const String.fromEnvironment('UPDATE_REPOSITORY_OWNER', defaultValue: 'fireside101'), this.repository = const String.fromEnvironment('UPDATE_REPOSITORY_NAME', defaultValue: 'fireside-group-mobile')});
  final String storageBase;
  final String owner;
  bool isStorageUri(Uri uri) {
    final base = Uri.tryParse(storageBase);
    return base != null && base.scheme == 'https' && base.host.isNotEmpty &&
      base.userInfo.isEmpty && !base.hasQuery && !base.hasFragment &&
      uri.scheme == 'https' && uri.host == base.host && uri.port == base.port &&
      uri.userInfo.isEmpty && !uri.hasFragment &&
      uri.path.startsWith('${base.path}/') &&
      !uri.pathSegments.any((s) => s == '..' || s == '.');
  }
  final String repository;
  Uri get latestReleaseApiUri => Uri.https('api.github.com', '/repos/$owner/$repository/releases/latest');
  bool isReleaseUri(Uri uri) => uri.scheme == 'https' && uri.host == 'github.com' && uri.pathSegments.length >= 6 && uri.pathSegments[0] == owner && uri.pathSegments[1] == repository && uri.pathSegments[2] == 'releases' && uri.pathSegments[3] == 'download';
}

class AppUpdateMetadata {
  const AppUpdateMetadata({required this.versionCode, required this.versionName, required this.releaseNotes, required this.apkUrl, this.apkSize, this.apkSha256, this.commit, this.signerSha256, this.bucket, this.objectKey, this.sessionBinding});
  final String? bucket;
  final String? objectKey;
  final String? sessionBinding;
  final String? commit;
  final String? signerSha256;
  final int versionCode;

  factory AppUpdateMetadata.fromRegistry(Map<String, dynamic> json, {required AppUpdateConfig config}) {
    final privateArtifact = json['provider'] == 'supabase-rest';
    final urlValue = json[privateArtifact ? 'download_url' : 'apk_url'];
    final url = Uri.tryParse(urlValue is String ? urlValue : '');
    final code = json['version_code'];
    final size = json['size'];
    final hash = json['sha256'];
    final signer = json['signer_sha256'];
    final commit = json['commit'];
    final version = json['version_name'];
    if (json['package'] != 'com.firesideafrica.firesidegroup' ||
      code is! int || code <= 0 || code > 2100000000 ||
      size is! int || size <= 0 || size > 536870912 ||
      hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
      signer is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(signer) ||
      commit is! String || !RegExp(r'^[a-f0-9]{40}$').hasMatch(commit) ||
      version is! String || !RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(version) ||
      url == null || !config.isStorageUri(url)) {
      throw const FormatException('Invalid authenticated update metadata.');
    }
    if (privateArtifact) {
      final key = 'com.firesideafrica.firesidegroup/$code/$commit/$hash.apk';
      final expiry = DateTime.tryParse(json['expires_at'] is String ? json['expires_at'] as String : '');
      final now = DateTime.now().toUtc();
      if (json.containsKey('apk_url') || json['bucket'] != 'fireside-mobile-releases' ||
          json['object_key'] != key ||
          url.host != 'supabase.firesideafrica.cloud' || url.port != 443 ||
          url.path != '/storage/v1/object/sign/fireside-mobile-releases/$key' ||
          url.toString().contains('%') || url.queryParametersAll.length != 1 ||
          url.queryParametersAll['token']?.length != 1 ||
          !RegExp(r'^[A-Za-z0-9_.-]{1,4096}$').hasMatch(url.queryParameters['token'] ?? '') ||
          expiry == null || !expiry.isAfter(now) ||
          expiry.isAfter(now.add(const Duration(seconds: 120)))) {
        throw const FormatException('Invalid private update delivery.');
      }
    } else if (json.containsKey('provider') || json.containsKey('bucket') || json.containsKey('object_key')) {
      throw const FormatException('Invalid private update identity.');
    }
    return AppUpdateMetadata(versionCode:code,versionName:version,releaseNotes:'',
      apkUrl:url,apkSize:size,apkSha256:hash,commit:commit,signerSha256:signer,
      bucket:privateArtifact ? json['bucket'] as String : null,
      objectKey:privateArtifact ? json['object_key'] as String : null,
      sessionBinding:json['session_binding'] as String?);
  }
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
  AppUpdateService({this.registry, http.Client? client, this.packageInfo, this.config = const AppUpdateConfig(), this._androidOverride, this._storageDirectory, MethodChannel? platformChannel}) : _client = client ?? http.Client(), _platformChannel = platformChannel ?? const MethodChannel('fireside_group/app_updates');
  static const _timeout = Duration(seconds: 8);
  static const automaticCheckCooldown = Duration(minutes: 15);
  final UpdateRegistry? registry;
  final http.Client _client;
  final PackageInfo? packageInfo;
  final AppUpdateConfig config;
  final bool? _androidOverride;
  final Directory? _storageDirectory;
  final MethodChannel _platformChannel;
  Future<AppUpdateCheckResult>? _checkInFlight;
  DateTime? _lastAutomaticCheck;
  AppUpdateCheckResult? _lastAutomaticResult;
  int? _deferredVersionCode;
  // A range finishes well within the private URL's 60-second authorization.
  static const _rangeBytes = 4 * 1024 * 1024;
  static const _rangeDeadline = Duration(seconds: 45);
  StreamIterator<List<int>>? _downloadIterator;
  Completer<void>? _requestAbort;
  bool _downloadInProgress = false;
  bool _cancelRequested = false;
  UpdateState state = UpdateState.idle;

  bool get _isAndroid => _androidOverride ?? defaultTargetPlatform == TargetPlatform.android;

  Future<AppUpdateCheckResult> checkForUpdate({bool automatic = false, bool force = false}) {
    final inFlight = _checkInFlight;
    if (inFlight != null) return inFlight;
    final now = DateTime.now();
    if (registry == null && automatic && !force && _lastAutomaticCheck != null &&
        now.difference(_lastAutomaticCheck!) < automaticCheckCooldown) {
      return Future.value(_lastAutomaticResult ?? const AppUpdateCheckResult.none());
    }
    final request = _performUpdateCheck();
    _checkInFlight = request;
    if (automatic) _lastAutomaticCheck = now;
    return request.then((result) {
      if (automatic) _lastAutomaticResult = result;
      return result;
    }).whenComplete(() => _checkInFlight = null);
  }

  Future<AppUpdateCheckResult> _performUpdateCheck() async {
    if (!_isAndroid) return const AppUpdateCheckResult.none();
    try {
      final installedInfo = packageInfo ?? await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(installedInfo.buildNumber);
      if (installedBuild == null) return const AppUpdateCheckResult.unavailable('The installed build number is unavailable.');
      if (registry != null) {
        final data = await registry!.latest().timeout(_timeout);
        if (data == null) return const AppUpdateCheckResult.none();
        final metadata = AppUpdateMetadata.fromRegistry(data, config:config);
        return metadata.versionCode > installedBuild ? AppUpdateCheckResult.update(metadata) : const AppUpdateCheckResult.none();
      }
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

  bool shouldPrompt(AppUpdateMetadata metadata, {bool manual = false}) {
    if (manual) {
      _deferredVersionCode = null;
      return true;
    }
    return _deferredVersionCode != metadata.versionCode;
  }

  void deferUpdate(AppUpdateMetadata metadata) {
    _deferredVersionCode = metadata.versionCode;
  }

  bool get isDownloadInProgress => _downloadInProgress;
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
    File? temp;
    try {
      final authorized = await _recheck(metadata);
      final directory = await _directory();
      await directory.create(recursive: true);
      final target = await _cachedFile(metadata);
      _checkDownloadIdentity(metadata);
      if (await _isValid(target, metadata)) {
        _checkDownloadIdentity(metadata);
        state = UpdateState.ready;
        onProgress?.call(UpdateProgress(UpdateState.ready, received: await target.length(), total: metadata.apkSize));
        return;
      }
      final tempFile = File('${target.path}.part');
      temp = tempFile;
      try { await tempFile.delete(); } on FileSystemException { /* already absent */ }
      _assertSession(metadata);
      final received = await _downloadRanges(tempFile, metadata, authorized, onProgress);
      if (_cancelRequested) throw const UpdateCancelled();
      if (!await _isValid(tempFile, metadata)) throw const FormatException('The downloaded APK failed integrity validation.');
      await _recheck(metadata);
      _checkDownloadIdentity(metadata);
      await tempFile.rename(target.path);
      state = UpdateState.ready;
      onProgress?.call(UpdateProgress(UpdateState.ready, received: received, total: metadata.apkSize));
    } catch (error) {
      if (temp != null) {
        try { await temp.delete(); } on FileSystemException { /* already absent */ }
      }
      state = UpdateState.failed;
      onProgress?.call(const UpdateProgress(UpdateState.failed, message: 'Update download failed. Check authorization and connectivity.'));
      rethrow;
    } finally {
      _downloadIterator = null;
      _requestAbort = null;
      _downloadInProgress = false;
    }
  }

  Future<void> cancelDownload() async {
    if (!_downloadInProgress) return;
    _cancelRequested = true;
    final abort = _requestAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    await _downloadIterator?.cancel();
  }

  void _checkDownloadIdentity(AppUpdateMetadata metadata) {
    _assertSession(metadata);
    if (_cancelRequested) throw const UpdateCancelled();
  }

  Future<int> _downloadRanges(File temp, AppUpdateMetadata metadata,
      AppUpdateMetadata authorized, void Function(UpdateProgress)? onProgress) async {
    final expected = metadata.apkSize;
    var offset = 0;
    String? etag;
    final output = await temp.open(mode: FileMode.write);
    try {
      while (expected == null ? offset == 0 : offset < expected) {
        _checkDownloadIdentity(metadata);
        final end = expected == null || expected - offset > _rangeBytes
            ? offset + _rangeBytes - 1 : expected - 1;
        // Reauthorize every bounded GET, not just after a token expires. The
        // registry must still advertise the identical artifact and session epoch.
        if (offset > 0) authorized = await _recheck(metadata);
        var attempts = 0;
        while (true) {
          _checkDownloadIdentity(metadata);
          final abort = Completer<void>();
          _requestAbort = abort;
          final watch = Stopwatch()..start();
          final deadline = Timer(_rangeDeadline, () {
            if (!abort.isCompleted) abort.complete();
          });
          StreamIterator<List<int>>? iterator;
          try {
            final request = http.AbortableRequest('GET', authorized.apkUrl,
                abortTrigger: abort.future)
              ..followRedirects = false
              ..headers['Range'] = 'bytes=$offset-$end'
              ..headers['Accept-Encoding'] = 'identity';
            if (etag != null) request.headers['If-Match'] = etag;
            final response = await _client.send(request).timeout(_timeout);
            iterator = StreamIterator(response.stream);
            _downloadIterator = iterator;
            _checkDownloadIdentity(metadata);
            if ((response.statusCode == 401 || response.statusCode == 403) &&
                registry != null && attempts == 0) {
              attempts++;
              await iterator.cancel();
              authorized = await _recheck(metadata);
              continue;
            }
            final encoding = response.headers['content-encoding'];
            if (encoding != null && encoding.toLowerCase() != 'identity') {
              throw const FormatException('Encoded APK responses are not supported.');
            }
            final int bodySize;
            if (response.statusCode == 206) {
              final range = RegExp(r'^bytes ([0-9]+)-([0-9]+)/([0-9]+)$')
                  .firstMatch(response.headers['content-range'] ?? '');
              final tag = response.headers['etag'];
              if (expected == null || range == null ||
                  int.tryParse(range[1]!) != offset ||
                  int.tryParse(range[2]!) != end ||
                  int.tryParse(range[3]!) != expected ||
                  tag == null || !RegExp(r'^"[\x21\x23-\x7e]+"$').hasMatch(tag) ||
                  (etag != null && tag != etag)) {
                throw const FormatException('Invalid APK range or artifact validator.');
              }
              etag = tag;
              bodySize = end - offset + 1;
            } else if (response.statusCode == 200 && offset == 0 &&
                (expected == null || expected <= _rangeBytes)) {
              // Explicit small, complete legacy compatibility only. A server
              // ignoring Range can never force a large single-stream download.
              bodySize = expected ?? _rangeBytes;
            } else {
              throw HttpException('Download failed with HTTP ${response.statusCode}.');
            }
            if (response.contentLength != null &&
                (response.contentLength! > bodySize ||
                 (expected != null && response.contentLength != bodySize))) {
              throw const FormatException('Invalid APK response length.');
            }
            var written = 0;
            while (true) {
              final remaining = _rangeDeadline - watch.elapsed;
              if (remaining <= Duration.zero) throw TimeoutException('APK range timed out.');
              final idle = remaining < const Duration(seconds: 30)
                  ? remaining : const Duration(seconds: 30);
              if (!await iterator.moveNext().timeout(idle)) break;
              _checkDownloadIdentity(metadata);
              final chunk = iterator.current;
              if (written + chunk.length > bodySize) {
                throw const FormatException('APK exceeds expected range size.');
              }
              // Await each private-file write before requesting another network
              // chunk. Unlike an unpaused IOSink listener, memory is bounded.
              await output.writeFrom(chunk);
              written += chunk.length;
              _checkDownloadIdentity(metadata);
              onProgress?.call(UpdateProgress(UpdateState.downloading,
                  received: offset + written, total: expected));
            }
            _checkDownloadIdentity(metadata);
            if (written == 0 || (expected != null && written != bodySize)) {
              throw const FormatException('Incomplete APK range body.');
            }
            offset += written;
            break;
          } catch (error) {
            _checkDownloadIdentity(metadata);
            // Retry only interrupted transport, once at the same verified
            // boundary. Never append bytes from an incomplete range.
            if (attempts == 0 && (error is http.ClientException ||
                error is SocketException || error is TimeoutException)) {
              attempts++;
              if (!abort.isCompleted) abort.complete();
              await iterator?.cancel();
              await output.truncate(offset);
              await output.setPosition(offset);
              authorized = await _recheck(metadata);
              continue;
            }
            // IOClient exceptions include the request URI (a bearer signed URL).
            // Never propagate that URI to the prompt, logs or caller diagnostics.
            if (error is http.ClientException || error is SocketException) {
              throw const HttpException('The APK connection was interrupted. Try again.');
            }
            rethrow;
          } finally {
            deadline.cancel();
            if (!abort.isCompleted) abort.complete();
            await iterator?.cancel();
            _downloadIterator = null;
            _requestAbort = null;
          }
        }
      }
      await output.flush();
      return offset;
    } finally {
      await output.close();
    }
  }

  void _assertSession(AppUpdateMetadata metadata) {
    final reader = registry;
    if (reader is UpdateSessionGuard &&
        (metadata.sessionBinding == null || metadata.sessionBinding != (reader as UpdateSessionGuard).sessionBinding)) {
      throw StateError('Update identity changed. Check again.');
    }
  }

  Future<AppUpdateMetadata> _recheck(AppUpdateMetadata metadata) async {
    if (registry == null) return metadata; // Explicit legacy compatibility, not a fallback.
    _assertSession(metadata);
    final data = await registry!.latest().timeout(_timeout);
    _assertSession(metadata);
    if (data == null) throw StateError('Update paused, revoked or no longer available.');
    final fresh = AppUpdateMetadata.fromRegistry(data, config:config);
    if (fresh.commit != metadata.commit || fresh.apkSha256 != metadata.apkSha256 ||
        fresh.apkSize != metadata.apkSize || fresh.versionCode != metadata.versionCode ||
        fresh.signerSha256 != metadata.signerSha256 || fresh.versionName != metadata.versionName ||
        fresh.bucket != metadata.bucket || fresh.objectKey != metadata.objectKey ||
        fresh.sessionBinding != metadata.sessionBinding ||
        (metadata.bucket == null && fresh.apkUrl != metadata.apkUrl)) {
      throw StateError('Update authorization changed. Check again.');
    }
    return fresh;
  }

  Future<UpdateInstallResult> installUpdate(AppUpdateMetadata metadata) async {
    await _recheck(metadata);
    final file = await _cachedFile(metadata);
    if (!await _isValid(file, metadata)) throw StateError('A complete validated APK download is required before installation.');
    _assertSession(metadata);
    final allowed = await _platformChannel.invokeMethod<bool>('canInstallPackages') ?? false;
    await _recheck(metadata);
    _assertSession(metadata);
    if (!allowed) { state = UpdateState.permissionRequired; await _platformChannel.invokeMethod<void>('openInstallPermissionSettings'); return UpdateInstallResult.permissionRequired; }
    state = UpdateState.installing;
    await _platformChannel.invokeMethod<void>('installApk', {'path': file.path, 'versionCode':metadata.versionCode, 'sha256':metadata.apkSha256, 'size':metadata.apkSize, 'signerSha256':metadata.signerSha256});
    return UpdateInstallResult.installerOpened;
  }
}
