import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'billing_repository.g.dart';

/// Story 9.6 — tenant recharge / lockout + advance-expiry warning.
///
/// The lockout is enforced SERVER-SIDE: `auth_tenant_id()` (0056) gates access,
/// and migration 0092 made `get_my_leads` (the last un-gated read) fail-closed on
/// tenant status too. So a suspended tenant has NO reachable data on any RPC —
/// this layer only READS the billing status to show the right screen/banner over
/// an already-locked door. `get_my_billing_status()` is readable by any tenant
/// member (0092) and deliberately bypasses the chokepoint so a suspended tenant is
/// still readable (that is exactly when the recharge screen shows).

/// Days-remaining threshold for the friendly "subscription ending soon" banner.
const billingWarningDays = 3;

/// Billing snapshot from `get_my_billing_status()`.
class BillingStatus {
  /// active | trial | suspended | cancelled.
  final String status;
  final String? planName;
  final DateTime? paidUntil;

  /// ceil((paid_until - now)/1d). Negative when overdue. Null when paid_until is NULL.
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

  /// True when access is cut. `active`/`trial` are the only allowed states,
  /// mirroring the server chokepoint `auth_tenant_id()` (status IN trial,active).
  bool get isLockedOut => status != 'active' && status != 'trial';

  /// True when past the paid window (drives "overdue by N days").
  bool get isOverdue => daysRemaining != null && daysRemaining! < 0;

  /// True when still active but within the advance-warning window — show the
  /// non-blocking "ending soon" banner. Excludes the overdue case (that is a
  /// separate/soon-to-be-locked state).
  bool get isExpiringSoon =>
      !isLockedOut &&
      daysRemaining != null &&
      daysRemaining! >= 0 &&
      daysRemaining! <= billingWarningDays;
}

class BillingRepository {
  BillingRepository(this._supabase);
  final SupabaseClient _supabase;

  /// Own-tenant billing status. Readable by any tenant member (0092). Stays
  /// readable even when the tenant is suspended (bypasses the chokepoint).
  Future<BillingStatus> getMyBillingStatus() async {
    final result = await _supabase.rpc('get_my_billing_status');
    return BillingStatus.fromJson(Map<String, dynamic>.from(result as Map));
  }
}

@riverpod
BillingRepository billingRepository(BillingRepositoryRef ref) {
  return BillingRepository(Supabase.instance.client);
}
