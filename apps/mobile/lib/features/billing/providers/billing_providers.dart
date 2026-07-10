import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/billing_repository.dart';

part 'billing_providers.g.dart';

/// Tenant access state for the current session (story 9.6).
enum TenantAccess {
  /// Active/trial, not near expiry — normal app.
  ok,

  /// Active/trial but within the advance-warning window — normal app + banner.
  warning,

  /// Suspended/lapsed — locked out, show the recharge screen.
  lockedOut,
}

class BillingGate {
  final TenantAccess access;

  /// Billing snapshot (present for [TenantAccess.warning] and [lockedOut]).
  final BillingStatus? billing;

  /// JWT `role == 'admin'` — selects recharge (admin) vs "contact admin" (employee) copy.
  final bool isAdmin;

  const BillingGate(this.access, {this.billing, this.isAdmin = false});

  static const ok = BillingGate(TenantAccess.ok);

  bool get isLockedOut => access == TenantAccess.lockedOut;
  bool get isWarning => access == TenantAccess.warning;
}

/// Resolves the current tenant's access state from its billing status.
///
/// SECURITY (AC #1): display decision only. Access is enforced server-side — the
/// `auth_tenant_id()` chokepoint (0056) plus migration 0092 (which closed the last
/// un-gated read, `get_my_leads`) mean a suspended tenant has NO reachable data on
/// any RPC. So this provider FAILS OPEN on read/network error (returns `ok` → normal
/// app) rather than risk locking out a paying customer over a transient blip; the
/// server stays the gate regardless.
///
/// `get_my_billing_status()` is now readable by any tenant member (0092), so both
/// admins and employees resolve reliably — no fragile data-RPC probe.
@riverpod
Future<BillingGate> billingGate(BillingGateRef ref) async {
  // Re-evaluate on auth events — TOKEN_REFRESHED (fires on app resume) and SIGNED_IN —
  // so a builder is let back in after the operator renews, without a reinstall.
  ref.watch(authStateChangesProvider);

  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return BillingGate.ok;

  final isAdmin = session.user.appMetadata['role'] == 'admin';
  try {
    final b = await ref.watch(billingRepositoryProvider).getMyBillingStatus();
    if (b.isLockedOut) {
      return BillingGate(TenantAccess.lockedOut, billing: b, isAdmin: isAdmin);
    }
    if (b.isExpiringSoon) {
      return BillingGate(TenantAccess.warning, billing: b, isAdmin: isAdmin);
    }
    return BillingGate.ok;
  } catch (_) {
    // Network / unexpected error → don't false-lock; server still enforces access.
    return BillingGate.ok;
  }
}
