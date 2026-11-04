import 'dart:convert';
import 'dart:io';

import 'package:fireside_group/core/mobile_targets.dart';
import 'package:fireside_group/data/models/profile_details.dart';
import 'package:fireside_group/data/providers.dart';
import 'package:fireside_group/data/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/profile/$name.json').readAsStringSync())
        as Map<String, dynamic>;

class ContractCache extends ProfileCacheNotifier {
  ContractCache(super.service, ProfileResponse response) {
    state = AsyncData(response);
  }
  ProfileResponse get value => state.value!;
}

void main() {
  for (final development in [false, true]) {
    test(
      'current rich GET and PATCH retain capabilities in development=$development',
      () async {
        final auth = SupabaseClient(
          'https://auth.example.test',
          'synthetic-anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'access_token': 'synthetic-token',
                'refresh_token': 'synthetic-refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {
                  'id': 'self',
                  'email': 'ada@example.test',
                  'app_metadata': {},
                  'user_metadata': {},
                  'aud': 'authenticated',
                  'created_at': '2026-01-01T00:00:00Z',
                },
              }),
              200,
            ),
          ),
        );
        addTearDown(auth.dispose);
        await auth.auth.signInWithPassword(
          email: 'ada@example.test',
          password: 'synthetic-only',
        );
        var next = 'get';
        var status = 200;
        final requests = <http.Request>[];
        final service = ProfileService(
          targets: development
              ? MobileTargets(
                  deploymentEnv: 'development',
                  tbtBaseUrl: MobileTargets.developmentTbtOrigin,
                  portalBaseUrl: MobileTargets.developmentPortalOrigin,
                )
              : MobileTargets(),
          authClient: auth,
          client: MockClient((request) async {
            requests.add(request);
            expect(
              request.url.toString(),
              '${development ? MobileTargets.developmentPortalOrigin : MobileTargets.productionPortalOrigin}/api/profile',
            );
            expect(request.headers['Authorization'], 'Bearer synthetic-token');
            if (status != 200) {
              return http.Response('{"error":"Access refused."}', status);
            }
            return http.Response(
              jsonEncode(fixture(next)),
              200,
              headers: {
                'content-type': 'application/json; charset=utf-8',
                'cache-control': 'no-store',
              },
            );
          }),
        );
        final fetched = await service.fetchProfile();
        expect(fetched.toJson(), fixture('get'));
        expect(fetched.details!.editable.namesOnly, isFalse);
        expect(fetched.details!.editable.thirdName, 'Byron');
        final cached = ProfileResponse.fromJson(
          jsonDecode(jsonEncode(fetched.toJson())) as Map<String, dynamic>,
        );
        expect(cached.toJson(), fetched.toJson());
        final cache = ContractCache(service, cached);
        addTearDown(cache.dispose);
        for (final value in ['Ngũgĩ', '']) {
          next = value.isEmpty ? 'patch_clear' : 'patch';
          final update = ProfileEditableDetails.fromJson({
            ...cached.details!.editable.toJson(),
            'third_name': value,
          });
          final saved = await service.updateDetails(update);
          expect(jsonDecode(requests.last.body), update.toJson());
          expect(
            jsonDecode(requests.last.body).keys,
            isNot(contains('_namesOnly')),
          );
          expect(saved.toJson(), fixture(next)['details']);
          cache.updateDetails(saved);
          expect(cache.value.options.toJson(), fetched.options.toJson());
          expect(cache.value.avatarUrl, fetched.avatarUrl);
          expect(cache.value.details!.editable.namesOnly, isFalse);
          expect(
            cache.value.details!.displayName,
            value.isEmpty ? 'Ada Lovelace' : 'Ada Lovelace Ngũgĩ',
          );
        }
        // Older rich clients must omit, not invent/clear, an absent third name.
        final old = {...cached.details!.editable.toJson()}
          ..remove('third_name');
        await service.updateDetails(ProfileEditableDetails.fromJson(old));
        expect(
          jsonDecode(requests.last.body).containsKey('third_name'),
          isFalse,
        );
        final beforeDenied = cache.value.toJson();
        for (final code in [401, 403, 409, 500]) {
          status = code;
          await expectLater(
            service.updateDetails(cached.details!.editable),
            throwsA(
              isA<ProfileServiceException>().having(
                (e) => e.message,
                'message',
                'Access refused.',
              ),
            ),
          );
          expect(cache.value.toJson(), beforeDenied);
        }
      },
    );
  }

  test(
    'DEV target rejects production and malformed overrides before HTTP',
    () async {
      for (final base in [
        'https://firesidegroup.firesideafrica.cloud',
        'http://firesidegroupdev.firesideafrica.cloud',
        'https://firesidegroupdev.firesideafrica.cloud:8443',
        'https://firesidegroupdev.firesideafrica.cloud/other',
        'https://firesidegroupdev.firesideafrica.cloud?x=1',
      ]) {
        var calls = 0;
        final service = ProfileService(
          targets: MobileTargets(
            deploymentEnv: 'development',
            tbtBaseUrl: MobileTargets.developmentTbtOrigin,
            portalBaseUrl: MobileTargets.developmentPortalOrigin,
          ),
          baseUrl: base,
          client: MockClient((_) async {
            calls++;
            return http.Response('{}', 200);
          }),
        );
        await expectLater(
          service.fetchProfile(),
          throwsA(isA<ProfileServiceException>()),
        );
        expect(calls, 0);
      }
    },
  );

  test(
    'production profile requests refuse signed-out identity before HTTP',
    () async {
      var calls = 0;
      final auth = SupabaseClient(
        'https://auth.example.test',
        'synthetic-anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(auth.dispose);
      final service = ProfileService(
        targets: MobileTargets(),
        authClient: auth,
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        service.fetchProfile(),
        throwsA(isA<ProfileServiceException>()),
      );
      await expectLater(
        service.updateDetails(ProfileEditableDetails.fromJson({})),
        throwsA(isA<ProfileServiceException>()),
      );
      expect(calls, 0);
    },
  );
}
