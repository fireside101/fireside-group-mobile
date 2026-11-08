import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/mobile_targets.dart';
import 'secure_update_auth.dart';
import 'onboarding_errors.dart';

class OnboardingException implements Exception {
  const OnboardingException(
    this.message, {
    this.statusCode,
    this.retryAfterSeconds,
  });
  final String message;
  final int? statusCode;
  final int? retryAfterSeconds;
  @override
  String toString() => message;
}

/// In-memory representation of the signed-in Workspace user.
class AuthSession {
  const AuthSession({required this.name, required this.email, this.photoUrl});

  final String name;
  final String email;
  final String? photoUrl;

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'photoUrl': photoUrl,
  };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    name: json['name'] as String,
    email: json['email'] as String,
    photoUrl: json['photoUrl'] as String?,
  );
}

/// Supabase-backed authentication for the mobile portal.
class AuthService {
  AuthService({SupabaseClient? client, http.Client? transport, this._vault})
    : _client = client ?? _tryClient(),
      _transport = transport ?? http.Client();

  final SupabaseClient? _client;
  final http.Client _transport;
  final SecureSessionVault? _vault;
  int _generation = 0;

  bool get isConfigured => _client != null;

  Future<Map<String, dynamic>> _post(
    String action,
    Map<String, String> body, {
    int successStatus = 200,
  }) async {
    try {
      final origin = MobileTargets.fromEnvironment().portalOrigin;
      final request =
          http.Request('POST', Uri.parse('$origin/api/auth/onboarding/$action'))
            ..followRedirects = false
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode(body);
      return await (() async {
        final response = await _transport.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 65536) {
            throw const OnboardingException(
              'Account service unavailable. Please try again.',
            );
          }
          bytes.addAll(chunk);
        }
        Map<String, dynamic> data = {};
        try {
          data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        } catch (_) {
          if (response.statusCode == successStatus) {
            throw const OnboardingException(
              'Account service unavailable. Please try again.',
            );
          }
          // Preserve status/Retry-After even for an upstream HTML error body.
        }
        if (response.statusCode != successStatus) {
          throw OnboardingException(
            onboardingErrorMessage(response.statusCode, data),
            statusCode: response.statusCode,
            retryAfterSeconds: onboardingRetryAfter(
              response.statusCode,
              response.headers['retry-after'],
            ),
          );
        }
        return data;
      })().timeout(const Duration(seconds: 30));
    } on OnboardingException {
      rethrow;
    } catch (_) {
      throw const OnboardingException(onboardingNetworkError);
    }
  }

  Future<String> discover(String email) async {
    final data = await _post('discover', {'email': email.trim()});
    final next = data['next'];
    if (next != 'login' && next != 'register') {
      throw const OnboardingException(
        'Account service unavailable. Please try again.',
      );
    }
    return next as String;
  }

  Future<AuthSession?> signIn({
    required String email,
    required String password,
  }) async {
    final client = _requireClient();
    final generation = ++_generation;
    final vault = _vault;
    final epoch = await vault?.currentEpoch();
    final data = await _post('login', {
      'email': email.trim(),
      'password': password,
    });
    if (generation != _generation) {
      throw StateError('Authentication operation superseded.');
    }
    final tokens = data['session'];
    if (tokens is! Map ||
        tokens['access_token'] is! String ||
        tokens['refresh_token'] is! String ||
        (tokens['access_token'] as String).isEmpty ||
        (tokens['refresh_token'] as String).isEmpty) {
      throw const OnboardingException(
        'Account service unavailable. Please try again.',
      );
    }
    // The coordinator must enroll the external login before SDK setSession:
    // its refresh interceptor deliberately refuses un-enrolled credentials.
    if (vault != null) {
      await vault.acceptPortalLogin(
        _transport,
        Uri.parse(Uri.parse(client.rest.url).origin),
        client.auth.headers['apikey']!,
        tokens['refresh_token'] as String,
        email.trim(),
        expectedEpoch: epoch,
      );
    }
    if (generation != _generation) {
      throw StateError('Authentication operation superseded.');
    }
    final response = await client.auth.setSession(
      tokens['refresh_token'] as String,
    );
    if (generation != _generation) {
      throw StateError('Authentication operation superseded.');
    }
    return _sessionFromUser(response.user);
  }

  Future<AuthSession?> register({
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    if (password.length < 8 || password.length > 1024) {
      throw OnboardingException(onboardingErrorMessages['PASSWORD_LENGTH']!);
    }
    if (confirmPassword.isEmpty) {
      throw OnboardingException(
        onboardingErrorMessages['CONFIRM_PASSWORD_REQUIRED']!,
      );
    }
    if (password != confirmPassword) {
      throw OnboardingException(onboardingErrorMessages['PASSWORD_MISMATCH']!);
    }
    final data = await _post('register', {
      'email': email.trim(),
      'password': password,
      'confirmPassword': confirmPassword,
    });
    if (data['next'] != 'login' || data.containsKey('session')) {
      throw const OnboardingException(
        'Account service unavailable. Return to email and try again.',
      );
    }
    return null; // Registration never establishes a session or invokes signup/reset.
  }

  Future<void> signOut() async {
    ++_generation;
    await _vault?.removePersistedSession();
    await _requireClient().auth.signOut();
  }

  Future<AuthSession?> restoreSession() async {
    final client = _client;
    if (client == null) return null;
    return _sessionFromUser(client.auth.currentUser);
  }

  /// Asks the portal to email a single-use recovery link. The portal answers
  /// 202 with the same message whether or not the account exists; the link
  /// opens the web reset page and the user then signs in here.
  Future<String> requestPasswordRecovery(String email) async {
    final data = await _post('recover', {
      'email': email.trim(),
    }, successStatus: 202);
    final message = data['message'];
    if (message is! String || message.trim().isEmpty) {
      return recoveryFallbackMessage;
    }
    return message.trim();
  }

  static const recoveryFallbackMessage =
      'If that email belongs to an eligible Fireside account, a password '
      'reset link is on its way.';

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError(
        'Portal sign-in is not configured. Build with SUPABASE_URL and '
        'SUPABASE_ANON_KEY.',
      );
    }
    return client;
  }

  static SupabaseClient? _tryClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static AuthSession? _sessionFromUser(User? user) {
    if (user == null) return null;
    final metadata = user.userMetadata ?? <String, dynamic>{};
    final fullName = metadata['full_name'];
    final name = metadata['name'];
    final displayName = fullName is String && fullName.trim().isNotEmpty
        ? fullName.trim()
        : name is String && name.trim().isNotEmpty
        ? name.trim()
        : user.email ?? 'Fireside user';

    final avatar = metadata['avatar_url'];
    return AuthSession(
      name: displayName,
      email: user.email ?? '',
      photoUrl: avatar is String && avatar.isNotEmpty ? avatar : null,
    );
  }
}
