import 'package:fireside_group/core/theme/app_theme.dart';
import 'package:fireside_group/data/models/fireside_application.dart';
import 'package:fireside_group/features/home/widgets/launcher_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _apps = [
  FiresideApplication(
    id: 'warehouse',
    name: 'Warehouse Management System',
    department: 'Operations',
    description: 'Track inventory levels across all regional stores in real time.',
    category: 'featured',
    url: 'https://warehouse.example.com',
    keywords: ['inventory'],
  ),
  FiresideApplication(
    id: 'scorecard',
    name: 'Scorecard',
    department: 'People',
    description: 'Performance and growth scorecards',
    category: 'platform',
    url: 'https://scorecard.example.com',
    keywords: ['people'],
  ),
  FiresideApplication(
    id: 'tadhkara',
    name: 'Tadhkara',
    department: 'Retail',
    description: 'Daily store capacity tracker',
    category: 'featured',
    url: 'https://tadhkara.example.com',
    keywords: ['capacity'],
  ),
];

void main() {
  testWidgets('renders tiles without overflow at phone width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTealTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LauncherShell(applications: _apps),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Warehouse Management System'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders tiles without overflow at desktop width', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTealTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LauncherShell(applications: _apps),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Warehouse Management System'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}