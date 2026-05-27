import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/auth/ui/password_change_screen.dart';
import '../features/home/ui/home_placeholder_screen.dart';
import '../features/settings/ui/settings_screen.dart';
import '../features/auth/utils/auth_validators.dart';

const _storage = FlutterSecureStorage();

/// Notifies GoRouter when Supabase auth state changes (sign-in, session restored, sign-out).
/// Fixes the cold-start race where currentSession is null before supabase_flutter restores
/// the persisted session — INITIAL_SESSION event triggers a redirect re-evaluation.
class _SupabaseAuthNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;

  _SupabaseAuthNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _authNotifier = _SupabaseAuthNotifier();

final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: _authNotifier,
  redirect: (context, state) async {
    final session = Supabase.instance.client.auth.currentSession;
    final path = state.matchedLocation;
    final isLoginRoute = path == '/login';
    final isPasswordChangeRoute = path == '/password-change';

    // No session → force to login
    if (session == null && !isLoginRoute) return '/login';

    if (session != null) {
      final userId = session.user.id;

      // Check both secure storage AND JWT app_metadata.
      // app_metadata survives app reinstall that clears secure storage.
      final flag = await _storage.read(key: mustChangePasswordKey(userId));
      final metaFlag =
          session.user.appMetadata['must_change_password'] as bool? ?? false;
      final mustChange = flag == 'true' || metaFlag;

      // On login screen with valid session → route based on flag
      if (isLoginRoute) return mustChange ? '/password-change' : '/home';

      // On any other screen: redirect to password-change if flag still set
      if (mustChange && !isPasswordChangeRoute) return '/password-change';
    }

    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/home', builder: (_, __) => const HomePlaceholderScreen()),
    GoRoute(
      path: '/password-change',
      builder: (_, state) {
        // isForced is passed as a query param (?forced=false for voluntary change from Settings).
        // Query params survive OS-triggered route restoration; in-memory extra does not.
        final isForced = state.uri.queryParameters['forced'] != 'false';
        return PasswordChangeScreen(isForced: isForced);
      },
    ),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
  ],
);
