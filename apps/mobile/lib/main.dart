import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/notifications_service.dart';

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

  await Firebase.initializeApp();

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  await NotificationsService.initialize();

  runApp(const ProviderScope(child: NirmanApp()));
}
