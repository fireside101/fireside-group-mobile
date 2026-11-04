import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_update_service.dart';
import 'update_registry.dart';

/// Dark by default. Activation requires a deployed, independently verified
/// mobile-update function and UPDATE_STORAGE_BASE matching its approved origin.
class UpdateRuntimeConfig {
  const UpdateRuntimeConfig({
    this.mode = const String.fromEnvironment(
      'UPDATE_REGISTRY',
      defaultValue: 'disabled',
    ),
    this.storageBase = const String.fromEnvironment('UPDATE_STORAGE_BASE'),
    this.supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
    this.supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
  });
  final String mode;
  final String storageBase;
  final String supabaseUrl;
  final String supabaseAnonKey;
  bool get backgroundReady =>
      mode == 'private' &&
      supabaseUrl == 'https://supabase.firesideafrica.cloud' &&
      supabaseAnonKey.isNotEmpty &&
      storageBase ==
          'https://supabase.firesideafrica.cloud/storage/v1/object/sign';
  bool get enabled => mode == 'private' || mode == 'github';
}

UpdateRegistry? createUpdateRegistry(
  UpdateRuntimeConfig config, {
  SupabaseClient? client,
}) {
  if (config.mode == 'github') {
    return null; // Explicit opt-in, never a fallback.
  }
  if (config.mode == 'private' &&
      client != null &&
      config.storageBase ==
          'https://supabase.firesideafrica.cloud/storage/v1/object/sign') {
    return SupabaseUpdateRegistry(client);
  }
  return const UnavailableUpdateRegistry();
}

class UnavailableUpdateRegistry implements UpdateRegistry {
  const UnavailableUpdateRegistry();
  @override
  Future<Map<String, dynamic>?> latest() async =>
      throw StateError('Updates are not configured.');
}

AppUpdateService createAppUpdateService(
  UpdateRuntimeConfig runtime, {
  SupabaseClient? client,
}) => AppUpdateService(
  registry: createUpdateRegistry(runtime, client: client),
  config: AppUpdateConfig(storageBase: runtime.storageBase),
);
