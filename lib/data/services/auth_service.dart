import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// In-memory representation of the signed-in Workspace user.
class AuthSession {
  const AuthSession({
    required this.name,
    required this.email,
    this.photoUrl,
  });

  final String name;
  final String email;
  final String? photoUrl;

  Map<String, dynamic> toJson() =>
      {'name': name, 'email': email, 'photoUrl': photoUrl};

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        name: json['name'] as String,
        email: json['email'] as String,
        photoUrl: json['photoUrl'] as String?,
      );
}

/// Wraps google_sign_in plus a secure local session cache.
///
/// No token exchange with a backend yet — intentionally minimal. Persisting
/// {name, email, photoUrl} lets the app restore a "has session" state across
/// launches without re-prompting the Google account chooser.
class AuthService {
  AuthService({
    GoogleSignIn? googleSignIn,
    FlutterSecureStorage? secureStorage,
  })  : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              hostedDomain: 'fireside.africa',
              scopes: ['email', 'profile'],
            ),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _sessionKey = 'auth_session';

  final GoogleSignIn _googleSignIn;
  final FlutterSecureStorage _secureStorage;

  Stream<GoogleSignInAccount?> get onCurrentUserChanged =>
      _googleSignIn.onCurrentUserChanged;

  Future<bool> isSignedIn() => _googleSignIn.isSignedIn();

  Future<AuthSession?> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;
    final session = AuthSession(
      name: account.displayName ?? account.email,
      email: account.email,
      photoUrl: account.photoUrl,
    );
    await _secureStorage.write(
      key: _sessionKey,
      value: jsonEncode(session.toJson()),
    );
    return session;
  }

  Future<void> signOut() async {
    await _secureStorage.delete(key: _sessionKey);
    await _googleSignIn.signOut();
  }

  Future<AuthSession?> restoreSession() async {
    final raw = await _secureStorage.read(key: _sessionKey);
    if (raw == null) return null;
    try {
      return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await _secureStorage.delete(key: _sessionKey);
      return null;
    }
  }
}