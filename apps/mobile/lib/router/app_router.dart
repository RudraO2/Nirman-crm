import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/home/ui/home_placeholder_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isLoginRoute = state.matchedLocation == '/login';
    final isPasswordChangeRoute = state.matchedLocation == '/password-change';

    if (session == null && !isLoginRoute) return '/login';
    if (session != null && isLoginRoute) return '/home';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomePlaceholderScreen(),
    ),
    GoRoute(
      // Story 1.5 — placeholder route so go_router doesn't 404 on redirect
      path: '/password-change',
      builder: (context, state) => const HomePlaceholderScreen(),
    ),
  ],
);
