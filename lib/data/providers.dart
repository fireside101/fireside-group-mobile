import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'models/admin_audit_log.dart';
import 'models/fireside_application.dart';
import 'models/health_status.dart';
import 'models/profile_details.dart';
import 'repositories/catalogue_repository.dart';
import 'repositories/health_repository.dart';
import 'repositories/local_catalogue_repository.dart';
import 'repositories/recent_apps_repository.dart';
import 'services/admin_audit_log_service.dart';
import 'services/profile_service.dart';
import 'services/app_update_service.dart';
import 'services/update_background_wakeup.dart';
import 'services/update_registry.dart';
import 'services/update_runtime.dart';
import 'services/update_schedule.dart';

/// Installed package metadata, shared and cached for this ProviderScope's life.
/// This deliberately does not read the update registry or the source pubspec.
final installedPackageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

final updateRuntimeConfigProvider = Provider<UpdateRuntimeConfig>(
  (ref) => const UpdateRuntimeConfig(),
);

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } catch (_) {
    /* Fail closed below. */
  }
  final service = createAppUpdateService(
    ref.watch(updateRuntimeConfigProvider),
    client: client,
  );
  final registry = service.registry;
  if (registry is SupabaseUpdateRegistry) {
    ref.onDispose(() => unawaited(registry.dispose()));
  }
  return service;
});

final updateScheduleProvider = Provider<UpdateSchedule>(
  (ref) => UpdateSchedule(store: PreferencesScheduleStore()),
);
final updateBackgroundWakeupProvider = Provider<UpdateBackgroundWakeup>(
  (ref) => UpdateBackgroundWakeup(),
);

final adminAuditLogServiceProvider = Provider<AdminAuditLogService>(
  (ref) => AdminAuditLogService(),
);

final adminAuditLogsProvider = FutureProvider<List<AdminAuditLog>>((ref) {
  return ref.watch(adminAuditLogServiceProvider).fetchLogs();
});

final profileServiceProvider = Provider<ProfileService>(
  (ref) => ProfileService(),
);

const profileCacheDuration = Duration(minutes: 5);

final profileCacheProvider =
    StateNotifierProvider<ProfileCacheNotifier, AsyncValue<ProfileResponse?>>(
      (ref) => ProfileCacheNotifier(ref.watch(profileServiceProvider)),
    );

class ProfileCacheNotifier extends StateNotifier<AsyncValue<ProfileResponse?>> {
  ProfileCacheNotifier(this._service) : super(const AsyncValue.data(null));

  final ProfileService _service;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _userId;
  DateTime? _lastFetched;
  Future<void>? _inFlight;

  Future<void> load({bool force = false}) {
    final userId = _currentUserId;
    if (userId == null) {
      _userId = null;
      _lastFetched = null;
      state = const AsyncValue.data(null);
      return Future.value();
    }

    if (_userId != userId) {
      _userId = userId;
      _lastFetched = null;
      state = const AsyncValue.data(null);
    }

    final age = _lastFetched == null
        ? null
        : DateTime.now().difference(_lastFetched!);
    if (!force && state.value != null && age != null) {
      if (age < profileCacheDuration) return Future.value();
      return _fetch(userId, showLoading: false);
    }

    if (_inFlight != null) return _inFlight!;
    return _loadCachedThenFetch(userId);
  }

  Future<void> _loadCachedThenFetch(String userId) async {
    final cached = await _readCache(userId);
    if (cached != null && _userId == userId) {
      state = AsyncValue.data(cached.value);
      _lastFetched = cached.savedAt;
      final age = DateTime.now().difference(cached.savedAt);
      if (age < profileCacheDuration) return;
    }
    await _fetch(userId, showLoading: cached == null);
  }

  Future<void> _fetch(String userId, {required bool showLoading}) {
    if (_inFlight != null) return _inFlight!;
    if (showLoading && state.value == null) {
      state = const AsyncValue.loading();
    }

    final request = _service.fetchProfile().then(
      (response) async {
        if (_userId != userId) return;
        _lastFetched = DateTime.now();
        state = AsyncValue.data(response);
        await _writeCache(userId, response, _lastFetched!);
      },
      onError: (Object error, StackTrace stack) {
        if (_userId != userId) return;
        // Preserve stale data when a background refresh fails.
        if (state.value == null) state = AsyncError(error, stack);
      },
    );
    _inFlight = request.whenComplete(() => _inFlight = null);
    return _inFlight!;
  }

  void updateDetails(PersonalDetails details) {
    final current = state.value;
    if (current == null) return;
    final updated = ProfileResponse(
      details: details,
      options: current.options,
      avatarUrl: current.avatarUrl,
    );
    _setUpdated(updated);
  }

  void updateAvatar(String avatarUrl) {
    final current = state.value;
    if (current == null) return;
    _setUpdated(
      ProfileResponse(
        details: current.details,
        options: current.options,
        avatarUrl: avatarUrl,
      ),
    );
  }

  void _setUpdated(ProfileResponse response) {
    _lastFetched = DateTime.now();
    state = AsyncValue.data(response);
    final userId = _userId;
    if (userId != null) {
      unawaited(_writeCache(userId, response, _lastFetched!));
    }
  }

  String? get _currentUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String _cacheKey(String userId) => 'profile_cache_$userId';

  Future<_CachedProfile?> _readCache(String userId) async {
    try {
      final raw = await _storage.read(key: _cacheKey(userId));
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '');
      final profile = json['profile'];
      if (savedAt == null || profile is! Map<String, dynamic>) return null;
      return _CachedProfile(ProfileResponse.fromJson(profile), savedAt);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(
    String userId,
    ProfileResponse profile,
    DateTime savedAt,
  ) async {
    try {
      await _storage.write(
        key: _cacheKey(userId),
        value: jsonEncode({
          'savedAt': savedAt.toIso8601String(),
          'profile': profile.toJson(),
        }),
      );
    } catch (_) {
      // The network-backed profile remains fully functional if local storage
      // is unavailable.
    }
  }
}

class _CachedProfile {
  const _CachedProfile(this.value, this.savedAt);

  final ProfileResponse value;
  final DateTime savedAt;
}

/// Swap this single line when a remote catalogue is ready.
final catalogueRepositoryProvider = Provider<CatalogueRepository>(
  (ref) => LocalCatalogueRepository(),
);

final catalogueProvider = FutureProvider<List<FiresideApplication>>(
  (ref) => ref.watch(catalogueRepositoryProvider).fetchCatalogue(),
);

const healthCacheDuration = Duration(seconds: 60);

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => const HealthRepository(),
);

/// Health lookups are cached for [healthCacheDuration] per app id.
/// Apps without a healthUrl are reported as `unknown` without any fetch.
final healthStatusProvider =
    StateNotifierProvider.family<
      HealthStatusNotifier,
      AsyncValue<HealthStatus>,
      FiresideApplication
    >((ref, app) {
      return HealthStatusNotifier(app, ref.watch(healthRepositoryProvider));
    });

class HealthStatusNotifier extends StateNotifier<AsyncValue<HealthStatus>> {
  HealthStatusNotifier(this._app, this._repository)
    : super(const AsyncValue.data(HealthStatus.unknown)) {
    probe();
  }

  final FiresideApplication _app;
  final HealthRepository _repository;
  DateTime? _lastFetched;

  void probe({bool force = false}) {
    final healthUrl = _app.healthUrl;
    if (healthUrl == null) return;

    final now = DateTime.now();
    if (!force &&
        _lastFetched != null &&
        now.difference(_lastFetched!) < healthCacheDuration) {
      return;
    }

    _lastFetched = now;
    state = const AsyncValue.loading();
    _repository
        .fetchHealth(healthUrl)
        .then(
          (status) => state = AsyncValue.data(status),
          onError: (Object e, StackTrace st) => state = AsyncError(e, st),
        );
  }
}

final recentAppsRepositoryProvider = Provider<RecentAppsRepository>(
  (ref) => RecentAppsRepository(),
);

final recentAppsProvider =
    StateNotifierProvider<
      RecentAppsNotifier,
      AsyncValue<List<FiresideApplication>>
    >((ref) => RecentAppsNotifier(ref));

class RecentAppsNotifier
    extends StateNotifier<AsyncValue<List<FiresideApplication>>> {
  RecentAppsNotifier(this._ref)
    : super(const AsyncValue.data(<FiresideApplication>[])) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final repository = _ref.read(recentAppsRepositoryProvider);
    final ids = await repository.read();
    final catalogue = await _ref.read(catalogueProvider.future);
    final byId = {for (final app in catalogue) app.id: app};
    state = AsyncValue.data(
      ids.map((id) => byId[id]).whereType<FiresideApplication>().toList(),
    );
  }

  Future<void> record(String appId) async {
    final repository = _ref.read(recentAppsRepositoryProvider);
    final ids = await repository.record(appId);
    final catalogue = await _ref.read(catalogueProvider.future);
    final byId = {for (final app in catalogue) app.id: app};
    state = AsyncValue.data(
      ids.map((id) => byId[id]).whereType<FiresideApplication>().toList(),
    );
  }
}
