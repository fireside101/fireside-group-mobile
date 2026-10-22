import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_details.dart';

class ProfileService {
  ProfileService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          (baseUrl ??
                  const String.fromEnvironment(
                    'PORTAL_API_BASE_URL',
                    defaultValue: 'https://firesidegroup.firesideafrica.cloud',
                  ))
              .replaceFirst(RegExp(r'/+$'), '');

  final http.Client _client;
  final String _baseUrl;

  Future<ProfileResponse> fetchProfile() async {
    final response = await _client.get(
      _uri('/api/profile'),
      headers: await _headers(),
    );
    return ProfileResponse.fromJson(_decode(response));
  }

  Future<PersonalDetails> updateDetails(ProfileEditableDetails details) async {
    final response = await _client.patch(
      _uri('/api/profile'),
      headers: {...await _headers(), 'Content-Type': 'application/json'},
      body: jsonEncode(details.toJson()),
    );
    final body = _decode(response);
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

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<Map<String, String>> _headers() async {
    final session = Supabase.instance.client.auth.currentSession;
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
