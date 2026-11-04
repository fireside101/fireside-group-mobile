import 'dart:async';

import 'package:fireside_group/data/providers.dart';
import 'package:fireside_group/features/shell/installed_version_label.dart';
import 'package:fireside_group/core/theme/app_theme.dart';
import 'package:fireside_group/features/settings/settings_screen.dart';
import 'package:fireside_group/features/shell/app_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Fireside Group',
      packageName: 'com.example.fireside',
      version: '7.8.9',
      buildNumber: '432',
      buildSignature: '',
    );
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: buildTealTheme(), home: screen),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('header shows the installed package version tag', (tester) async {
    await pumpScreen(tester, const Scaffold(body: AppHeader()));
    expect(find.text('v7.8.9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings shows installed version and build, not release metadata',
    (tester) async {
      await pumpScreen(tester, const SettingsScreen());
      await tester.scrollUntilVisible(find.text('Installed version'), 200);
      expect(find.text('Version 7.8.9 (build 432)'), findsOneWidget);
      expect(find.text('v7.8.9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings fits at 320 pixels with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScreen(tester, const SettingsScreen());
    await tester.scrollUntilVisible(find.text('Installed version'), 150);
    await tester.ensureVisible(find.text('Version 7.8.9 (build 432)'));
    await tester.pump();
    expect(find.text('Version 7.8.9 (build 432)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending and failed metadata stay honest in both presentations', (
    tester,
  ) async {
    final pending = Completer<PackageInfo>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          installedPackageInfoProvider.overrideWith((ref) => pending.future),
        ],
        child: MaterialApp(
          theme: buildTealTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Installed version'), 150);
    expect(find.text('Loading installed version…'), findsOneWidget);
    expect(find.text('v7.8.9'), findsNothing);
    pending.completeError(StateError('unavailable'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Version unavailable'), findsOneWidget);
    expect(find.text('v7.8.9'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final values in [('', ''), ('7.8.9', ''), ('', '432')]) {
    testWidgets(
      'missing metadata $values never fabricates a version or build',
      (tester) async {
        PackageInfo.setMockInitialValues(
          appName: 'Fireside Group',
          packageName: 'com.example.fireside',
          version: values.$1,
          buildNumber: values.$2,
          buildSignature: '',
        );
        await pumpScreen(
          tester,
          const Scaffold(
            body: Column(
              children: [
                InstalledVersionLabel(compact: true),
                InstalledVersionLabel(),
              ],
            ),
          ),
        );
        final version = values.$1.isEmpty
            ? 'Version unavailable'
            : 'Version ${values.$1}';
        final build = values.$2.isEmpty
            ? 'build unavailable'
            : 'build ${values.$2}';
        expect(find.text('$version ($build)'), findsOneWidget);
        expect(
          find.text('v7.8.9'),
          values.$1.isEmpty ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('header fits at 320 pixels with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScreen(tester, const Scaffold(body: AppHeader()));
    expect(find.text('v7.8.9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
