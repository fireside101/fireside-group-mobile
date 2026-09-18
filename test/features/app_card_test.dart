import 'package:fireside_group/core/theme/app_theme.dart';
import 'package:fireside_group/data/models/fireside_application.dart';
import 'package:fireside_group/features/app_card/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

Future<void> _pumpCard(WidgetTester tester, FiresideApplication app) async {
  await tester.pumpWidget(
    ProviderScope(
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
  testWidgets('renders name, description and department', (tester) async {
    await _pumpCard(tester, _withUrl);
    expect(find.text('Warehouse'), findsOneWidget);
    expect(find.text('Track inventory'), findsOneWidget);
    expect(find.text('OPERATIONS'), findsOneWidget);
  });

  testWidgets('renders an app without a URL', (tester) async {
    await _pumpCard(tester, _noUrl);
    expect(find.text('Fireside BI Reporting'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('ANALYTICS'), findsOneWidget);
  });

  testWidgets('shows a chevron and has no status indicator', (tester) async {
    await _pumpCard(tester, _withUrl);
    expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
  });
}