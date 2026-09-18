import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/fireside_application.dart';
import 'models/health_status.dart';
import 'repositories/catalogue_repository.dart';
import 'repositories/health_repository.dart';
import 'repositories/installed_apps_repository.dart';
import 'repositories/local_catalogue_repository.dart';
import 'repositories/recent_apps_repository.dart';

/// Swap this single line when a remote catalogue is ready.
final catalogueRepositoryProvider =
    Provider<CatalogueRepository>((ref) => LocalCatalogueRepository());

final catalogueProvider = FutureProvider<List<FiresideApplication>>(
  (ref) => ref.watch(catalogueRepositoryProvider).fetchCatalogue(),
);

const healthCacheDuration = Duration(seconds: 60);

final healthRepositoryProvider =
    Provider<HealthRepository>((ref) => const HealthRepository());

/// Health lookups are cached for [healthCacheDuration] per app id.
/// Apps without a healthUrl are reported as `unknown` without any fetch.
final healthStatusProvider =
    StateNotifierProvider.family<HealthStatusNotifier, AsyncValue<HealthStatus>, FiresideApplication>((ref, app) {
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
    _repository.fetchHealth(healthUrl).then(
          (status) => state = AsyncValue.data(status),
          onError: (Object e, StackTrace st) => state = AsyncError(e, st),
        );
  }
}

final recentAppsRepositoryProvider =
    Provider<RecentAppsRepository>((ref) => RecentAppsRepository());

final recentAppsProvider = StateNotifierProvider<RecentAppsNotifier, AsyncValue<List<FiresideApplication>>>(
  (ref) => RecentAppsNotifier(ref),
);

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

final installedAppsRepositoryProvider =
    Provider<InstalledAppsRepository>((ref) => const InstalledAppsRepository());

final installedAppsProvider =
    StateNotifierProvider<InstalledAppsNotifier, AsyncValue<Set<String>>>(
  (ref) => InstalledAppsNotifier(ref.watch(installedAppsRepositoryProvider)),
);

class InstalledAppsNotifier extends StateNotifier<AsyncValue<Set<String>>> {
  InstalledAppsNotifier(this._repository) : super(const AsyncValue.loading()) {
    _load();
  }

  final InstalledAppsRepository _repository;

  Future<void> _load() async {
    state = AsyncValue.data(await _repository.read());
  }

  Future<void> install(String appId) async {
    state = AsyncValue.data(await _repository.install(appId));
  }
}