import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';
import 'package:fireside_group/data/services/update_background_wakeup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'registers durable credential-free check and retires legacy reminder',
    () async {
      // Construct singleton before replacing the platform implementation.
      Workmanager();
      final previous = WorkmanagerPlatform.instance;
      final platform = RecordingWorkmanager();
      WorkmanagerPlatform.instance = platform;
      addTearDown(() => WorkmanagerPlatform.instance = previous);
      final wakeup = UpdateBackgroundWakeup();
      await wakeup.register(const Duration(hours: 3));
      await wakeup.register(const Duration(hours: 6));
      expect(platform.calls, 1);
      expect(platform.dispatcher, updateWakeupDispatcher);
      expect(platform.name, updateWakeupTask);
      expect(platform.delay, const Duration(hours: 3));
      expect(platform.frequency, const Duration(minutes: 15));
      expect(platform.policy, ExistingPeriodicWorkPolicy.keep);
      expect(platform.network, NetworkType.connected);
      expect(platform.backoff, BackoffPolicy.exponential);
      expect(platform.input, isNull); // Never tokens or metadata/signed URLs.
      expect(platform.cancelled, legacyUpdateWakeupTask);
    },
  );
}

class RecordingWorkmanager extends WorkmanagerPlatform {
  String? cancelled;
  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancelled = uniqueName;
  }

  int calls = 0;
  Function? dispatcher;
  String? name;
  Duration? delay, frequency;
  ExistingPeriodicWorkPolicy? policy;
  NetworkType? network;
  BackoffPolicy? backoff;
  Map<String, dynamic>? input;
  @override
  Future<void> initialize(
    Function callbackDispatcher, {
    bool isInDebugMode = false,
  }) async {
    dispatcher = callbackDispatcher;
  }

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    ForegroundServiceConfig? foregroundServiceConfig,
  }) async {
    calls++;
    name = uniqueName;
    delay = initialDelay;
    this.frequency = frequency;
    policy = existingWorkPolicy;
    network = constraints?.networkType;
    backoff = backoffPolicy;
    input = inputData;
  }
}
