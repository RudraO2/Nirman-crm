import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/billing_repository.dart';

part 'billing_providers.g.dart';

/// Which lockout face to show (story 9.6).
enum PausedKind {
  /// Tenant is active/trial — normal app.
  notPaused,

  /// Tenant admin whose subscription lapsed → full recharge screen.
  adminLockedOut,

  /// Employee inside a suspended tenant → simple "contact your admin" screen.
  employeeLockedOut,
}

class PausedState {
  final PausedKind kind;

  /// Only populated for [PausedKind.adminLockedOut] (billing is admin-only).
  final BillingStatus? billing;

  const PausedState(this.kind, [this.billing]);

  static const notPaused = PausedState(PausedKind.notPaused);

  bool get isLockedOut => kind != PausedKind.notPaused;
}

/// Resolves whether the current tenant is locked out, and which screen to show.
///
/// SECURITY NOTE (AC #1): this is a *display* decision only. Access is enforced
/// server-side by `auth_tenant_id()` (0056); if this provider is wrong or errors,
/// the worst case is a suspended user briefly sees an empty app shell whose data
/// RPCs all still fail-closed at Postgres. It therefore fails OPEN on the display
/// (treats ambiguous/network errors as "not paused" → normal retry, AC #7) rather
/// than risk locking out a paying, active customer over a transient blip.
@riverpod
Future<PausedState> pausedState(PausedStateRef ref) async {
  // Re-evaluate on auth events — notably TOKEN_REFRESHED (fires on app resume)
  // and SIGNED_IN, so a builder is let back in after the operator renews without
  // a reinstall, and re-checked whenever the app comes to the foreground.
  ref.watch(authStateChangesProvider);

  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return PausedState.notPaused;

  final repo = ref.watch(billingRepositoryProvider);
  final role = session.user.appMetadata['role'] as String?;

  if (role == 'admin') {
    try {
      final billing = await repo.getMyBillingStatus();
      return billing.isLockedOut
          ? PausedState(PausedKind.adminLockedOut, billing)
          : PausedState.notPaused;
    } catch (_) {
      // Network / unexpected error reading billing → don't false-lock an admin.
      return PausedState.notPaused;
    }
  }

  // Employee: cannot read billing (admin-only). Detect via the data-RPC
  // chokepoint failure instead.
  try {
    final locked = await repo.probeLockedOut();
    return locked
        ? const PausedState(PausedKind.employeeLockedOut)
        : PausedState.notPaused;
  } catch (_) {
    // Non-lockout error (network etc.) → treat as not paused; the normal
    // screens will surface their own retry.
    return PausedState.notPaused;
  }
}
