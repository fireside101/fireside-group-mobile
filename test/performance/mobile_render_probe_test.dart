import 'dart:convert';

import 'package:fireside_group/app.dart';
import 'package:fireside_group/core/router/app_router.dart';
import 'package:fireside_group/data/services/auth_service.dart';
import 'package:fireside_group/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class OfflineAuth extends AuthService {
  int restores = 0, discoveries = 0;
  @override
  Future<AuthSession?> restoreSession() async {
    restores++;
    return null;
  }

  @override
  Future<String> discover(String email) async {
    discoveries++;
    return 'login';
  }
}

void main() {
  testWidgets('bounded host Flutter launch/render probe (not device profile)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final launchMicros = <int>[];
    final resumeMicros = <int>[];
    for (var sample = 0; sample < 5; sample++) {
      final auth = OfflineAuth();
      final container = ProviderContainer(
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );
      final watch = Stopwatch()..start();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FiresideGroupApp(),
        ),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      watch.stop();
      launchMicros.add(watch.elapsedMicroseconds);
      expect(find.text('Continue'), findsOneWidget);
      expect(tester.takeException(), isNull);
      watch.reset();
      watch.start();
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle(
        const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      watch.stop();
      resumeMicros.add(watch.elapsedMicroseconds);
      expect(auth.restores, 1);
      expect(auth.discoveries, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      container.read(routerProvider).dispose();
      container.dispose();
    }
    // Host wall time including widget-test overhead, no raster/device/SSO claim.
    // ignore: avoid_print
    print(
      'MOBILE_HOST_RENDER_PROBE ${jsonEncode({'samples': launchMicros.length, 'launch_to_email_ready_us': launchMicros, 'pause_resume_us': resumeMicros, 'phone_size': '390x844', 'mode': 'flutter-test-host-debug-not-device-profile', 'network_calls': 0})}',
    );
  });
}
