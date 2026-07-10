import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'billing_repository.g.dart';

/// Story 9.6 — tenant recharge / lockout.
///
/// The access lockout itself is enforced SERVER-SIDE by the `auth_tenant_id()`
/// chokepoint (migration 0056): a `suspended`/`cancelled` tenant resolves to a
/// NULL tenant, so every data RPC fail-closes. This layer only READS that state
/// so the app can show a friendly "recharge" face over an already-locked door —
/// removing this UI never unlocks any data (see story AC #1).

/// Billing snapshot returned by `get_my_billing_status()` (0088). Admin-only.
class BillingStatus {
  /// Raw tenant status: active | trial | suspended | cancelled (+ grace if present).
  final String status;
  final String? planName;
  final DateTime? paidUntil;

  /// ceil((paid_until - now) / 1 day) from the DB. Negative when overdue. Null
  /// when `paid_until` is NULL (never paid / pure trial).
  final int? daysRemaining;

  const BillingStatus({
    required this.status,
    this.planName,
    this.paidUntil,
    this.daysRemaining,
  });

  factory BillingStatus.fromJson(Map<String, dynamic> json) {
    final rawPaid = json['paid_until'] as String?;
    return BillingStatus(
      status: (json['status'] as String?) ?? 'unknown',
      planName: json['plan_name'] as String?,
      paidUntil: rawPaid == null ? null : DateTime.tryParse(rawPaid),
      daysRemaining: (json['days_remaining'] as num?)?.toInt(),
    );
  }

  /// True when this tenant should see the recharge screen (access is cut).
  /// `active` and `trial` are the only "let them in" states, mirroring the
  /// server chokepoint `auth_tenant_id()` (status IN ('trial','active')).
  bool get isLockedOut => status != 'active' && status != 'trial';

  /// True when overdue (past the paid window) — drives "overdue by N days" copy.
  bool get isOverdue => daysRemaining != null && daysRemaining! < 0;
}

/// Postgres error code raised by data RPCs when the tenant is locked out
/// (`auth_tenant_id()` returned NULL → `RAISE ... USING ERRCODE='P0001'`,
/// message `missing_tenant_context`). This is the signal that an EMPLOYEE
/// (who cannot read billing) is inside a suspended tenant. See 0019:147.
const missingTenantContextCode = 'P0001';
const missingTenantContextMessage = 'missing_tenant_context';

/// Classifies whether a caught error means "tenant is locked out" vs a generic
/// error we must NOT misread as paused (story AC #7 — no false positives).
/// Pure function so it is unit-testable without a live backend.
bool isTenantLockedOutError(Object error) {
  if (error is PostgrestException) {
    if (error.code == missingTenantContextCode) return true;
    if (error.message.contains(missingTenantContextMessage)) return true;
  }
  return false;
}

class BillingRepository {
  BillingRepository(this._supabase);
  final SupabaseClient _supabase;

  /// Reads the caller's own billing status. Admin-only server-side; calling as
  /// an employee raises `42501` (permission_denied) — callers must gate on role.
  Future<BillingStatus> getMyBillingStatus() async {
    final result = await _supabase.rpc('get_my_billing_status');
    return BillingStatus.fromJson(Map<String, dynamic>.from(result as Map));
  }

  /// Cheap probe used to detect lockout for EMPLOYEES (who cannot read billing).
  /// Loads at most one lead; a `missing_tenant_context` (P0001) failure means
  /// the tenant is suspended. Returns true = locked out, false = has access.
  /// Rethrows anything that is NOT a lockout signal so the caller can show a
  /// normal retry instead of a false "paused" (AC #7).
  Future<bool> probeLockedOut() async {
    try {
      await _supabase.rpc('get_my_leads', params: {'p_limit': 1, 'p_offset': 0});
      return false;
    } catch (e) {
      if (isTenantLockedOutError(e)) return true;
      rethrow;
    }
  }
}

@riverpod
BillingRepository billingRepository(BillingRepositoryRef ref) {
  return BillingRepository(Supabase.instance.client);
}
