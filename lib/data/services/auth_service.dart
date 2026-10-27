import 'package:supabase_flutter/supabase_flutter.dart';

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
  AuthService({SupabaseClient? client}) : _client = client ?? _tryClient();

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  Future<AuthSession?> signIn({
    required String email,
    required String password,
  }) async {
    final client = _requireClient();
    final response = await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    return _sessionFromUser(response.user);
  }

  Future<AuthSession?> register({
    required String email,
    required String password,
  }) async {
    final client = _requireClient();
    final response = await client.auth.signUp(
      email: email.trim(),
      password: password,
    );
    // Supabase can create the user without creating a session when email
    // confirmation is enabled. Keep the user on the login screen in that case.
    return response.session == null ? null : _sessionFromUser(response.user);
  }

  Future<void> signOut() async {
    await _requireClient().auth.signOut();
  }

  Future<AuthSession?> restoreSession() async {
    final client = _client;
    if (client == null) return null;
    return _sessionFromUser(client.auth.currentUser);
  }

  Future<void> sendPasswordReset(String email) async {
    await _requireClient().auth.resetPasswordForEmail(email.trim());
  }

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
