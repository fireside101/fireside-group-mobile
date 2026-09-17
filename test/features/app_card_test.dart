import 'package:fireside_group/core/theme/app_theme.dart';
import 'package:fireside_group/data/models/fireside_application.dart';
import 'package:fireside_group/data/models/health_status.dart';
import 'package:fireside_group/data/providers.dart';
import 'package:fireside_group/data/repositories/health_repository.dart';
import 'package:fireside_group/features/app_card/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHealthRepository implements HealthRepository {
  const _FakeHealthRepository(this.status);

  final HealthStatus status;

  @override
  Future<HealthStatus> fetchHealth(String healthUrl) async => status;
}

const _withUrl = FiresideApplication(
  id: 'warehouse',
  name: 'Warehouse',
  department: 'Operations',
  description: 'Track inventory',
  category: 'featured',
  url: 'https://warehouse.example.com',
  healthUrl: 'https://warehouse.example.com/health',
  keywords: ['stock'],
);

const _noUrl = FiresideApplication(
  id: 'bi',
  name: 'Fireside BI Reporting',
  department: 'Analytics',
  description: 'Reports',
  category: 'platform',
  repository: 'Internal service',
);

Future<void> _pumpCard(
  WidgetTester tester,
  FiresideApplication app, {
  HealthStatus status = HealthStatus.unknown,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        healthRepositoryProvider
            .overrideWithValue(_FakeHealthRepository(status)),
      ],
      child: MaterialApp(
        theme: buildTealTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: AppCard(application: app),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows Available for an available app', (tester) async {
    await _pumpCard(tester, _withUrl, status: HealthStatus.available);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('shows Unavailable for an unavailable app', (tester) async {
    await _pumpCard(tester, _withUrl, status: HealthStatus.unavailable);
    expect(find.text('Unavailable'), findsOneWidget);
  });

  testWidgets('shows Unknown when status is unknown', (tester) async {
    await _pumpCard(tester, _withUrl, status: HealthStatus.unknown);
    expect(find.text('Unknown'), findsOneWidget);
  });

  testWidgets('renders the Internal service state when url is null',
      (tester) async {
    await _pumpCard(tester, _noUrl);
    expect(find.text('Internal'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('renders name and department', (tester) async {
    await _pumpCard(tester, _withUrl);
    expect(find.text('Warehouse'), findsOneWidget);
    expect(find.text('OPERATIONS'), findsOneWidget);
  });
}