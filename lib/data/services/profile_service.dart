import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/mobile_targets.dart';
import '../models/profile_details.dart';

class ProfileService {
  ProfileService({
    http.Client? client,
    String? baseUrl,
    this.authClient,
    MobileTargets? targets,
  }) : _client = client ?? http.Client(),
       _targets = targets ?? MobileTargets.fromEnvironment(),
       _baseUrl = baseUrl?.replaceFirst(RegExp(r'/+$'), '');

  final http.Client _client;
  final SupabaseClient? authClient;
  final String? _baseUrl;
  final MobileTargets _targets;

  Future<ProfileResponse> fetchProfile() async {
    final response = await _client.get(
      _uri('/api/profile'),
      headers: await _headers(),
    );
    final body = _decode(response);
    if (body['profile'] is Map<String, dynamic>) {
      return ProfileResponse(
        details: _portalDetails(body),
        options: const ProfileOptions(),
        avatarUrl: '',
      );
    }
    if (!body.containsKey('details')) {
      throw const ProfileServiceException('Incompatible profile API response.');
    }
    return ProfileResponse.fromJson(body);
  }

  Future<PersonalDetails> updateDetails(ProfileEditableDetails details) async {
    final response = await _client.patch(
      _uri('/api/profile'),
      headers: {...await _headers(), 'Content-Type': 'application/json'},
      body: jsonEncode(
        details.namesOnly
            ? (details.toJson()..removeWhere(
                (key, _) => !const {
                  'first_name',
                  'last_name',
                  'third_name',
                }.contains(key),
              ))
            : details.toJson(),
      ),
    );
    final body = _decode(response);
    if (body['profile'] is Map<String, dynamic>) return _portalDetails(body);
    if (body['details'] is! Map<String, dynamic>) {
      throw const ProfileServiceException('Incompatible profile API response.');
    }
    return PersonalDetails.fromJson(body['details'] as Map<String, dynamic>);
  }

  Future<String> uploadAvatar({
    required List<int> bytes,
    required String fileName,
  }) async {
    if (bytes.length > 2 * 1024 * 1024) {
      throw ProfileServiceException('Images must be 2 MB or smaller.');
    }
    final request = http.MultipartRequest('POST', _uri('/api/profile/avatar'))
      ..headers.addAll(await _headers())
      ..files.add(
        http.MultipartFile.fromBytes(
          'avatar',
          bytes,
          filename: fileName,
          contentType: _mediaType(fileName),
        ),
      );
    final response = await http.Response.fromStream(await request.send());
    return (_decode(response)['avatarUrl'] as String?) ?? '';
  }

  Future<void> removeAvatar() async {
    final response = await _client.delete(
      _uri('/api/profile/avatar'),
      headers: await _headers(),
    );
    _decode(response);
  }

  Future<void> updatePassword({
    required String password,
    required String confirmPassword,
  }) async {
    final response = await _client.post(
      _uri('/api/profile/password'),
      headers: {...await _headers(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'password': password,
        'confirm_password': confirmPassword,
      }),
    );
    _decode(response);
  }

  PersonalDetails _portalDetails(Map<String, dynamic> body) {
    final profile = body['profile'] as Map<String, dynamic>;
    if (profile['full_name'] is! String ||
        profile['first_name'] is! String ||
        profile['last_name'] is! String ||
        !profile.containsKey('third_name')) {
      throw const ProfileServiceException('Incompatible profile API response.');
    }
    return PersonalDetails.fromJson({
      'fullName': profile['full_name'],
      'editable': {
        'first_name': profile['first_name'],
        'last_name': profile['last_name'],
        'third_name': profile['third_name'],
        '_namesOnly': true,
      },
    });
  }

  Uri _uri(String path) {
    // The compatible existing portal backend is deployed and owner-approved.
    // Production and DEV remain separate exact-origin contracts; no fallback.
    final base = Uri.tryParse(_baseUrl ?? _targets.portalOrigin);
    if (base == null ||
        base.scheme != 'https' ||
        base.hasPort ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.path.isNotEmpty && base.path != '/') ||
        !(base.origin == _targets.portalOrigin ||
            (_targets.isDevelopment && base.host == 'portal.example.test'))) {
      throw const ProfileServiceException(
        'Profile target must match the selected reviewed portal origin.',
      );
    }
    return base.replace(path: path);
  }

  Future<Map<String, String>> _headers() async {
    final session =
        (authClient ?? Supabase.instance.client).auth.currentSession;
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      throw ProfileServiceException(
        'Your session has expired. Please sign in again.',
      );
    }
    return {'Authorization': 'Bearer $token'};
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> body = const {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProfileServiceException(
        body['error'] as String? ?? 'Profile request failed.',
      );
    }
    return body;
  }

  MediaType _mediaType(String fileName) {
    switch (fileName.toLowerCase().split('.').last) {
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      default:
        throw ProfileServiceException('Use a PNG, JPEG, or WebP image.');
    }
  }
}

class ProfileServiceException implements Exception {
  const ProfileServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
