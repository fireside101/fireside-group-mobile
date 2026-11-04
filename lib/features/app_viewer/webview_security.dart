import 'dart:math';

import '../../data/repositories/local_catalogue_repository.dart';

/// Only bundled, reviewed origins are trusted; remote catalogue URLs are data.
class WebViewSecurity {
  WebViewSecurity(String appId)
    : _approved = catalogue.where((app) => app.id == appId).firstOrNull?.url,
      _nativeApproved = appId == 'attendance-ptw';

  final String? _approved;
  final bool _nativeApproved;
  String? _account;
  String? _page;
  int _generation = 0;
  bool _closed = false;
  String? _capability;
  int _lastRequest = 0;
  String? get documentCapability => _capability;

  int? authorizeBridge(String capability, int requestId) {
    if (_capability == null ||
        capability != _capability ||
        requestId <= _lastRequest ||
        requestId > 1000000) {
      return null;
    }
    final lease = captureLease();
    if (lease == null) return null;
    _lastRequest = requestId;
    return lease;
  }

  bool allows(String url) {
    final uri = Uri.tryParse(url);
    final approved = Uri.tryParse(_approved ?? '');
    return !_closed &&
        uri != null &&
        approved != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.host.isNotEmpty &&
        uri.host == approved.host &&
        uri.port == 443;
  }

  void navigationStarted() {
    _generation++;
    _page = null;
    _capability = null;
    _lastRequest = 0;
  }

  void pageFinished(String url) {
    _generation++;
    _page = allows(url) ? url : null;
    _lastRequest = 0;
    final random = Random.secure();
    _capability = _nativeApproved && _page != null && _account != null
        ? List.generate(
            32,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join()
        : null;
  }

  void accountChanged(String? account) {
    // Even same-user auth events may mean session refresh/revocation.
    _account = account;
    navigationStarted();
  }

  void close() {
    _closed = true;
    navigationStarted();
  }

  bool canUseNative({required String? sourceOrigin}) =>
      _nativeApproved &&
      _account != null &&
      _page != null &&
      sourceOrigin != null &&
      allows(sourceOrigin);

  int? captureLease() =>
      _nativeApproved && _account != null && _page != null && !_closed
      ? _generation
      : null;

  bool isCurrent(int? lease) => lease != null && lease == captureLease();
}
