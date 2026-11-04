import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'data/services/secure_update_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      final origin = Uri.parse(supabaseUrl);
      final nativePersistence =
          !kIsWeb &&
          {
            TargetPlatform.android,
            TargetPlatform.iOS,
            TargetPlatform.macOS,
          }.contains(defaultTargetPlatform);
      final vault = nativePersistence
          ? SecureSessionVault.production(projectOrigin: origin.origin)
          : null;
      await vault?.initialize();
      await (vault ??
              SecureSessionVault.production(projectOrigin: origin.origin))
          .removeLegacyPlaintext(origin);
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseAnonKey,
        debug: false,
        httpClient: vault == null
            ? http.Client()
            : CoordinatedAuthClient(
                http.Client(),
                vault,
                origin,
                supabaseAnonKey,
              ),
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          localStorage: vault ?? const EmptyLocalStorage(),
          pkceAsyncStorage: vault == null
              ? EphemeralPkceStorage()
              : SecurePkceStorage(vault.secrets),
        ),
      );
    } catch (_) {
      // Keep the app renderable when Auth cannot initialize. The login screen
      // will show a recoverable configuration error instead of a blank app.
      debugPrint('Secure authentication initialization unavailable.');
    }
  }

  runApp(const ProviderScope(child: FiresideGroupApp()));
}
