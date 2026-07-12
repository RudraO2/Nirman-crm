import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/alarms/ui/alarm_ring_screen.dart';
import '../features/alarms/ui/alarm_settings_screen.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/billing/ui/paused_screen.dart';
import '../features/auth/ui/password_change_screen.dart';
import '../features/auth/utils/auth_validators.dart';
import '../features/home/ui/app_shell.dart';
import '../features/home/ui/home_screen.dart';
import '../features/home/ui/you_screen.dart';
import '../features/hierarchy/ui/organization_screen.dart';
import '../features/inventory/ui/availability_grid_screen.dart';
import '../features/inventory/ui/inventory_projects_screen.dart';
import '../features/team/ui/team_leads_screen.dart';
import '../features/reception/ui/verify_visit_screen.dart';
import '../features/booking/ui/booking_dashboard_screen.dart';
import '../features/amendments/ui/amendments_execution_screen.dart';
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

/// Story 9.6 — set by the app root (which watches `billingGateProvider`) to true
/// when the tenant is locked out. The router reads it in `redirect` so EVERY route
/// (not just the tab shell) bounces to `/paused` — a locked-out user never lands on
/// a raw error screen. Wired as a `refreshListenable` so flipping it re-runs redirect.
final billingLockNotifier = ValueNotifier<bool>(false);

final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: Listenable.merge([_authNotifier, billingLockNotifier]),
  redirect: (context, state) async {
    final session = Supabase.instance.client.auth.currentSession;
    final path = state.matchedLocation;
    final isLoginRoute = path == '/login';
    final isPasswordChangeRoute = path == '/password-change';
    final isPausedRoute = path == '/paused';
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

      // Eyeball feedback B1 — receptionist is gate-not-own: the 3-tab shell is
      // 2/3 dead for her (server denies all lead reads). Her home IS the
      // check-in screen. Only an explicit 'receptionist' tier reroutes —
      // absent tier (12.3 backfill not run) keeps today's shell, fail-safe.
      final isReceptionist =
          (session.user.appMetadata['role_tier'] as String?) == 'receptionist';

      // On login screen with valid session → route based on flag
      if (isLoginRoute) {
        if (mustChange) return '/password-change';
        return isReceptionist ? '/reception/verify' : '/home';
      }

      // On any other screen: redirect to password-change if flag still set
      if (mustChange && !isPasswordChangeRoute) return '/password-change';

      // Receptionist landing anywhere in the 3-tab shell → her real home.
      if (isReceptionist &&
          (path == '/home' || path == '/followups' || path == '/you')) {
        return '/reception/verify';
      }

      // Story 9.6 — tenant locked out (subscription lapsed): send every route to
      // the recharge screen. Password-change/alarm-ring stay reachable; /paused
      // itself must not self-redirect. Data is denied server-side regardless.
      if (billingLockNotifier.value &&
          !mustChange &&
          !isPausedRoute &&
          !isAlarmRingRoute &&
          !isPasswordChangeRoute) {
        return '/paused';
      }
      // Recovered (renewed) → leave the paused screen.
      if (!billingLockNotifier.value && isPausedRoute) return '/home';
    }

    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    // Story 9.6 — recharge/lockout screen (tenant subscription lapsed).
    GoRoute(path: '/paused', builder: (_, __) => const PausedRouteScreen()),
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
    // Story 12.4-mobile — builder-head hierarchy management (Organization).
    // Head-only entry (gated in you_screen); set_user_hierarchy re-checks role='admin'.
    GoRoute(
      path: '/organization',
      builder: (_, __) => const OrganizationScreen(),
    ),
    // Story 12.6-mobile — team-scoped lead visibility (get_team_leads).
    // Best-effort entry gate in you_screen; RPC scopes correctly for every tier.
    GoRoute(
      path: '/team-leads',
      builder: (_, __) => const TeamLeadsScreen(),
    ),
    // Story 13.4-mobile — reception check-in (verify_visit by customer code).
    // Best-effort entry gate in you_screen; verify_visit re-checks tier server-side.
    GoRoute(
      path: '/reception/verify',
      builder: (_, __) => const VerifyVisitScreen(),
    ),
    // Story 16.2-mobile — execution-team amendment surface (member-gated server-side).
    // Best-effort entry gate (head) in you_screen; the RPCs re-check membership/tier.
    GoRoute(
      path: '/amendments',
      builder: (_, __) => const AmendmentsExecutionScreen(),
    ),
    // Story 15.5-mobile — booking dashboard (active holds + countdown + hold→sold).
    // Best-effort entry gate in you_screen; get_active_holds/get_booking_stats scope
    // by visible_user_ids() server-side; confirm_booking re-checks the tier.
    GoRoute(
      path: '/booking',
      builder: (_, __) => const BookingDashboardScreen(),
    ),
    // Story 14.3-mobile — builder-ops availability grid (project picker → live grid).
    GoRoute(
      path: '/inventory',
      builder: (_, __) => const InventoryProjectsScreen(),
    ),
    GoRoute(
      path: '/inventory/:projectId',
      builder: (_, state) => AvailabilityGridScreen(
        projectId: state.pathParameters['projectId']!,
        projectName: state.uri.queryParameters['name'],
      ),
    ),
    GoRoute(
      path: '/leads/filtered',
      builder: (_, state) => FilteredLeadsScreen(
        filter: state.extra as LeadFilter,
      ),
    ),
  ],
);
