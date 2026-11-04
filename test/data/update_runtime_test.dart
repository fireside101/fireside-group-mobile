import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireside_group/data/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireside_group/data/services/update_runtime.dart';
import 'package:fireside_group/data/services/update_registry.dart';

void main() {
  test(
    'production provider uses fail-closed factory when private Auth is missing',
    () {
      final container = ProviderContainer(
        overrides: [
          updateRuntimeConfigProvider.overrideWithValue(
            const UpdateRuntimeConfig(mode: 'private'),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(appUpdateServiceProvider).registry,
        isA<UnavailableUpdateRegistry>(),
      );
    },
  );
  test('approved private config selects authenticated registry, not a public fallback', () async {
    final client = SupabaseClient(
      'https://supabase.firesideafrica.cloud',
      'public-test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    final registry = createUpdateRegistry(
      const UpdateRuntimeConfig(
        mode: 'private',
        storageBase:
            'https://supabase.firesideafrica.cloud/storage/v1/object/sign',
      ),
      client: client,
    );
    expect(registry, isA<SupabaseUpdateRegistry>());
    final authenticated = registry! as SupabaseUpdateRegistry;
    addTearDown(authenticated.dispose);
    await expectLater(
      authenticated.latest(),
      throwsStateError,
    ); // No employee session.
    final denied = createUpdateRegistry(
      const UpdateRuntimeConfig(
        mode: 'private',
        storageBase: 'https://unapproved.example/storage/v1/object/sign',
      ),
      client: client,
    );
    expect(denied, isA<UnavailableUpdateRegistry>());
  });
  test('default registry is dark, never implicitly GitHub', () async {
    expect(const UpdateRuntimeConfig().mode, 'disabled');
    final registry = createUpdateRegistry(const UpdateRuntimeConfig());
    expect(registry, isNotNull);
    await expectLater(registry!.latest(), throwsStateError);
  });
  test(
    'private missing session/config fails closed rather than GitHub',
    () async {
      final registry = createUpdateRegistry(
        const UpdateRuntimeConfig(mode: 'private'),
      );
      expect(registry, isA<UpdateRegistry>());
      await expectLater(registry!.latest(), throwsStateError);
    },
  );
  test('GitHub must be explicitly selected', () {
    expect(
      createUpdateRegistry(const UpdateRuntimeConfig(mode: 'github')),
      isNull,
    );
  });
  test('unknown registry fails closed', () async {
    await expectLater(
      createUpdateRegistry(const UpdateRuntimeConfig(mode: 'typo'))!.latest(),
      throwsStateError,
    );
  });
}
