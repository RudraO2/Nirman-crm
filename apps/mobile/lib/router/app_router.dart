import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/auth/ui/password_change_screen.dart';
import '../features/home/ui/home_placeholder_screen.dart';
import '../features/settings/ui/settings_screen.dart';

const _storage = FlutterSecureStorage();

final appRouter = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    final session = Supabase.instance.client.auth.currentSession;
    final path = state.matchedLocation;
    final isLoginRoute = path == '/login';
    final isPasswordChangeRoute = path == '/password-change';

    // No session → force to login
    if (session == null && !isLoginRoute) return '/login';

    if (session != null) {
      final userId = session.user.id;
      final flag = await _storage.read(key: 'must_change_password_$userId');
      final mustChange = flag == 'true';

      // On login screen with valid session → check flag first
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
        final extra = state.extra as Map<String, dynamic>?;
        final isForced = extra?['isForced'] as bool? ?? true;
        return PasswordChangeScreen(isForced: isForced);
      },
    ),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
  ],
);
