import 'dart:convert';

import 'package:fireside_group/core/mobile_targets.dart';
import 'package:fireside_group/data/models/profile_details.dart';
import 'package:fireside_group/data/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'profile API rejects mismatched and malformed production overrides',
    () async {
      for (final base in [
        '',
        'https://firesidegroupdev.firesideafrica.cloud',
        'http://portal.example.test',
      ]) {
        var calls = 0;
        final service = ProfileService(
          baseUrl: base,
          client: MockClient((request) async {
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
  test('existing authenticated self-profile API round trips third_name and never targets a person', () async {
    final auth = SupabaseClient(
      'https://auth.example.test',
      'synthetic-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'access_token': 'synthetic-token',
            'refresh_token': 'synthetic-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'self',
              'email': 'self@example.test',
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
      email: 'self@example.test',
      password: 'synthetic-only',
    );
    final calls = <http.Request>[];
    var status = 200;
    var portalContract = false;
    final service = ProfileService(
      targets: MobileTargets(
        deploymentEnv: 'development',
        tbtBaseUrl: MobileTargets.developmentTbtOrigin,
        portalBaseUrl: MobileTargets.developmentPortalOrigin,
      ),
      authClient: auth,
      baseUrl: 'https://portal.example.test/',
      client: MockClient((request) async {
        calls.add(request);
        expect(
          request.url.toString(),
          'https://portal.example.test/api/profile',
        );
        expect(request.headers['Authorization'], 'Bearer synthetic-token');
        if (status != 200) {
          return http.Response('{"error":"Not authorized."}', status);
        }
        if (portalContract) {
          if (request.method == 'PATCH') {
            expect(jsonDecode(request.body), {
              'first_name': 'A',
              'last_name': 'Z',
              'third_name': '王',
            });
          }
          return http.Response(
            jsonEncode({
              'profile': {
                'id': 'self',
                'first_name': 'A',
                'last_name': 'Z',
                'third_name': '王',
                'staff_email': 'self@example.test',
                'full_name': 'Authoritative PI name',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'details': {
                'fullName': 'A 王 Z',
                'editable': {
                  'first_name': 'A',
                  'third_name': '王',
                  'last_name': 'Z',
                },
              },
              'options': {},
              'avatarUrl': '',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['third_name'], '王');
        expect(body.keys, isNot(contains('id')));
        expect(body.keys, isNot(contains('person_id')));
        expect(body.keys, isNot(contains('staff_email')));
        return http.Response(
          jsonEncode({
            'details': {'fullName': 'A 王 Z', 'editable': body},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final profile = await service.fetchProfile();
    final details = await service.updateDetails(profile.details!.editable);
    expect(details.displayName, 'A 王 Z');
    expect(calls.map((call) => call.method), ['GET', 'PATCH']);
    portalContract = true;
    final portal = await service.fetchProfile();
    expect(portal.details, isNotNull);
    expect(portal.details!.displayName, 'Authoritative PI name');
    final refreshed = await service.updateDetails(portal.details!.editable);
    expect(refreshed.displayName, 'Authoritative PI name');
    status = 403;
    await expectLater(
      service.updateDetails(profile.details!.editable),
      throwsA(
        isA<ProfileServiceException>().having(
          (e) => e.message,
          'message',
          'Not authorized.',
        ),
      ),
    );
  });

  test('signed-out self-profile update is refused before HTTP', () async {
    final auth = SupabaseClient(
      'https://auth.example.test',
      'synthetic-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(auth.dispose);
    var calls = 0;
    final service = ProfileService(
      targets: MobileTargets(
        deploymentEnv: 'development',
        tbtBaseUrl: MobileTargets.developmentTbtOrigin,
        portalBaseUrl: MobileTargets.developmentPortalOrigin,
      ),
      authClient: auth,
      baseUrl: 'https://portal.example.test',
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      service.updateDetails(ProfileEditableDetails.fromJson({})),
      throwsA(isA<ProfileServiceException>()),
    );
    expect(calls, 0);
  });
}
