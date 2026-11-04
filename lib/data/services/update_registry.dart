import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Server authenticates the live Auth subject and checks current PI eligibility.
abstract interface class UpdateRegistry {
  Future<Map<String, dynamic>?> latest();
}

/// A local, noncredential binding; invalidated by logout/account change, not refresh.
abstract interface class UpdateSessionGuard {
  String? get sessionBinding;
}

class SupabaseUpdateRegistry implements UpdateRegistry, UpdateSessionGuard {
  SupabaseUpdateRegistry(this.client) {
    _subject = client.auth.currentUser?.id;
    _subscription = client.auth.onAuthStateChange.listen((event) {
      _observe(event.session?.user.id);
    });
  }
  final SupabaseClient client;
  late final StreamSubscription<AuthState> _subscription;
  String? _subject;
  int _epoch = 0;

  void _observe(String? subject) {
    if (subject != _subject) {
      _subject = subject;
      _epoch++;
    }
  }

  @override
  String? get sessionBinding {
    _observe(client.auth.currentUser?.id);
    return _subject == null ? null : '$_subject:$_epoch';
  }

  Future<void> dispose() => _subscription.cancel();

  @override
  Future<Map<String, dynamic>?> latest() async {
    final binding = sessionBinding;
    if (binding == null) throw StateError('Sign in to check updates.');
    // SDK supplies the current employee access token, never a service/publisher key.
    final response = await client.functions.invoke('mobile-update', body: const <String, dynamic>{});
    if (binding != sessionBinding) throw StateError('Update identity changed.');
    if (response.status != 200) throw StateError('Update authorization unavailable.');
    final envelope = response.data;
    if (envelope is! Map<String, dynamic> || !envelope.containsKey('release')) {
      throw const FormatException('Invalid registry response.');
    }
    final data = envelope['release'];
    if (data == null) return null;
    if (data is! Map<String, dynamic> || data['provider'] != 'supabase-rest') {
      throw const FormatException('Invalid private registry response.');
    }
    return {...data, 'session_binding': binding};
  }
}
