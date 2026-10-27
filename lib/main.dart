import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseAnonKey,
      );
    } catch (error, stack) {
      // Keep the app renderable when Auth cannot initialize. The login screen
      // will show a recoverable configuration error instead of a blank app.
      debugPrint('Supabase initialization failed: $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  runApp(const ProviderScope(child: FiresideGroupApp()));
}
