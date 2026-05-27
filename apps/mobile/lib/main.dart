import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'shared/services/screen_security_service.dart';

// Supabase credentials injected at build time via --dart-define.
// flutter run \
//   --dart-define=SUPABASE_URL=https://vhgruadourflpxuzuxfn.supabase.co \
//   --dart-define=SUPABASE_ANON_KEY=<anon-key>
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  assert(_supabaseUrl.isNotEmpty, 'SUPABASE_URL must be set via --dart-define');
  assert(_supabaseAnonKey.isNotEmpty, 'SUPABASE_ANON_KEY must be set via --dart-define');

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  // Story 1.8: restore screen security when a session survives app restart
  final existingSession = Supabase.instance.client.auth.currentSession;
  if (existingSession != null) {
    final role = existingSession.user.appMetadata['role'] as String? ?? 'employee';
    await ScreenSecurityService.applyForRole(role);
  }

  runApp(const ProviderScope(child: NirmanApp()));
}
