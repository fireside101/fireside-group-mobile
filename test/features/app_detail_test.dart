import 'package:fireside_group/core/theme/app_theme.dart';
import 'package:fireside_group/data/providers.dart';
import 'package:fireside_group/data/repositories/catalogue_repository.dart';
import 'package:fireside_group/data/repositories/installed_apps_repository.dart';
import 'package:fireside_group/data/models/fireside_application.dart';
import 'package:fireside_group/features/app_detail/app_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalogueRepository implements CatalogueRepository {
  const _FakeCatalogueRepository(this.apps);

  final List<FiresideApplication> apps;

  @override
  Future<List<FiresideApplication>> fetchCatalogue() async => apps;
}

void main() {
  const warehouse = FiresideApplication(
    id: 'warehouse',
    name: 'Warehouse',
    department: 'Operations',
    description: 'Track inventory',
    category: 'featured',
    url: 'https://warehouse.example.com',
    healthUrl: 'https://warehouse.example.com/health',
    keywords: ['stock'],
  );

  Widget buildApp(Set<String> installed) {
    return ProviderScope(
      overrides: [
        catalogueRepositoryProvider
            .overrideWithValue(const _FakeCatalogueRepository([warehouse])),
        installedAppsRepositoryProvider.overrideWithValue(
          _RecordingInstalledAppsRepository(installed),
        ),
      ],
      child: MaterialApp(
        theme: buildTealTheme(),
        home: const AppDetailScreen(appId: 'warehouse'),
      ),
    );
  }

  testWidgets('shows Install by default and disables the Open flow',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp({}));
    await tester.pumpAndSettle();

    expect(find.text('Install'), findsOneWidget);
    expect(find.text('Already installed'), findsNothing);
    expect(find.text('Open'), findsNothing);
    expect(find.text('About this app'), findsOneWidget);
  });

  testWidgets('shows Already installed when the app is installed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp({'warehouse'}));
    await tester.pumpAndSettle();

    expect(find.text('Already installed'), findsOneWidget);
    expect(find.text('Install'), findsNothing);
  });

  testWidgets('tapping Install records the app as installed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp({}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();

    expect(find.text('Already installed'), findsOneWidget);
    expect(find.text('Warehouse has been installed.'), findsOneWidget);
  });
}

class _RecordingInstalledAppsRepository extends InstalledAppsRepository {
  _RecordingInstalledAppsRepository(this._installed);

  Set<String> _installed;

  @override
  Future<Set<String>> read() async => _installed;

  @override
  Future<Set<String>> install(String appId) async {
    _installed = {..._installed, appId};
    return _installed;
  }
}