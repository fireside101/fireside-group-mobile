import 'package:fireside_group/core/theme/app_theme.dart';
import 'package:fireside_group/data/providers.dart';
import 'package:fireside_group/data/repositories/catalogue_repository.dart';
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

  const bi = FiresideApplication(
    id: 'bi',
    name: 'Fireside BI Reporting',
    department: 'Analytics',
    description: 'Reports',
    category: 'platform',
    repository: 'Internal service',
  );

  Widget buildApp(List<FiresideApplication> apps, String appId) {
    return ProviderScope(
      overrides: [
        catalogueRepositoryProvider
            .overrideWithValue(_FakeCatalogueRepository(apps)),
      ],
      child: MaterialApp(
        theme: buildTealTheme(),
        home: AppDetailScreen(appId: appId),
      ),
    );
  }

  testWidgets('shows an Open action for an app with a URL', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp([warehouse], 'warehouse'));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Install'), findsNothing);
    expect(find.text('Already installed'), findsNothing);
    expect(find.text('About this app'), findsOneWidget);
  });

  testWidgets('shows a disabled Internal service action without a URL',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp([bi], 'bi'));
    await tester.pumpAndSettle();

    expect(find.text('Internal service'), findsNWidgets(2));
    expect(find.text('Open'), findsNothing);
    expect(find.text('Install'), findsNothing);
  });
}