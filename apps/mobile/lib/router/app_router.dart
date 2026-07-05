import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/alarms/ui/alarm_ring_screen.dart';
import '../features/alarms/ui/alarm_settings_screen.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/auth/ui/password_change_screen.dart';
import '../features/auth/utils/auth_validators.dart';
import '../features/home/ui/app_shell.dart';
import '../features/home/ui/home_screen.dart';
import '../features/home/ui/you_screen.dart';
import '../features/leads/ui/archived_screen.dart';
import '../features/leads/ui/filtered_leads_screen.dart';
import '../features/leads/ui/followups_screen.dart';
import '../features/leads/ui/lead_detail_screen.dart';
import '../features/settings/ui/settings_screen.dart';

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
    // The full-screen ring screen must show even on cold-start before the
    // persisted session is restored (the alarm fires precisely when the app was
    // killed/locked). It carries its own payload and reads no network, so it is
    // exempt from the auth gate. Tapping through to a lead still hits the gate.
    final isAlarmRingRoute = path == '/alarm-ring';

    // No session → force to login
    if (session == null && !isLoginRoute && !isAlarmRingRoute) return '/login';

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
    // UI redesign §6.2 — 3-tab bottom shell hosting the existing screens.
    // indexedStack keeps every branch mounted so HomeScreen's alarm-sync
    // listener / resume observer keep firing regardless of the active tab.
    StatefulShellRoute.indexedStack(
      builder: (_, __, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/followups', builder: (_, __) => const FollowupsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/you', builder: (_, __) => const YouScreen()),
        ]),
      ],
    ),
    GoRoute(
      path: '/password-change',
      builder: (_, state) {
        // isForced is passed as a query param (?forced=false for voluntary change from Settings).
        // Query params survive OS-triggered route restoration; in-memory extra does not.
        final isForced = state.uri.queryParameters['forced'] != 'false';
        return PasswordChangeScreen(isForced: isForced);
      },
    ),
    GoRoute(
      path: '/lead/:id',
      builder: (_, state) => LeadDetailScreen(
        leadId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(
      path: '/settings/alarms',
      builder: (_, __) => const AlarmSettingsScreen(),
    ),
    GoRoute(
      path: '/alarm-ring',
      builder: (_, state) {
        // `extra` is in-memory only and does not survive OS route restoration
        // (process death while on this route). Without args there is no alarm to
        // act on — fall back home rather than crash on a null cast.
        final args = state.extra;
        if (args is! AlarmRingArgs) return const HomeScreen();
        return AlarmRingScreen(args: args);
      },
    ),
    GoRoute(path: '/archived', builder: (_, __) => const ArchivedScreen()),
    GoRoute(
      path: '/leads/filtered',
      builder: (_, state) => FilteredLeadsScreen(
        filter: state.extra as LeadFilter,
      ),
    ),
  ],
);
