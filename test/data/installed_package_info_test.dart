import 'dart:async';

import 'package:fireside_group/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void mockPackage(String version, String build) {
  PackageInfo.setMockInitialValues(
    appName: 'Fireside Group',
    packageName: 'com.example.fireside',
    version: version,
    buildNumber: build,
    buildSignature: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('installed package provider loads platform values and caches across reads', () async {
    mockPackage('7.8.9', '432');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(
      installedPackageInfoProvider,
      (_, _) {},
    );
    expect(container.read(installedPackageInfoProvider).isLoading, isTrue);
    final info = await container.read(installedPackageInfoProvider.future);
    expect(info.version, '7.8.9');
    expect(info.buildNumber, '432');
    subscription.close();

    mockPackage('8.0.0', '999');
    // No auto-dispose: navigating away and back retains the installed snapshot.
    expect(
      await container.read(installedPackageInfoProvider.future),
      same(info),
    );
    final newScope = ProviderContainer();
    addTearDown(newScope.dispose);
    expect(
      (await newScope.read(installedPackageInfoProvider.future)).version,
      '8.0.0',
    );
  });

  test('installed package provider exposes pending and failed reads without fake data', () async {
    final pending = Completer<PackageInfo>();
    final container = ProviderContainer(
      overrides: [
        installedPackageInfoProvider.overrideWith((ref) => pending.future),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(installedPackageInfoProvider).isLoading, isTrue);
    final future = container.read(installedPackageInfoProvider.future);
    final failure = StateError('metadata unavailable');
    final expectation = expectLater(future, throwsA(same(failure)));
    pending.completeError(failure);
    await expectation;
    expect(container.read(installedPackageInfoProvider).hasError, isTrue);
    expect(container.read(installedPackageInfoProvider).hasValue, isFalse);
  });
}
