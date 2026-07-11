// Story 14.3-mobile — inventory data access.
//
// Wraps the shipped get_project_units RPC (migration 0072). Read-only: this story
// ships NO write/hold path (that is Story 15.2). Margin + agency scoping are
// enforced server-side inside the SECURITY DEFINER RPC; this client only renders
// what the RPC returns.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/unit_hold_model.dart';
import 'models/unit_model.dart';

part 'inventory_repository.g.dart';

/// Raised when the availability grid read is denied or the project is missing.
/// A `partner_agency` user opening a project not shared to their agency gets
/// [notShared] = true → the UI shows a friendly empty state, not a red crash.
class InventoryAccessException implements Exception {
  final String message;
  final bool notShared;
  final bool notFound;

  const InventoryAccessException(
    this.message, {
    this.notShared = false,
    this.notFound = false,
  });

  /// Maps the RPC's RAISEd errors (surfaced as PostgrestException.message) to a
  /// typed failure. The RPC raises the bare tokens `project_not_shared` /
  /// `project_not_found` / `not_authenticated`.
  factory InventoryAccessException.fromPostgrest(PostgrestException e) {
    final m = e.message;
    if (m.contains('project_not_shared')) {
      return InventoryAccessException(m, notShared: true);
    }
    if (m.contains('project_not_found')) {
      return InventoryAccessException(m, notFound: true);
    }
    return InventoryAccessException(m);
  }

  @override
  String toString() => message;
}

/// Story 15.2 — raised when a hold attempt is rejected. [conflict] = the unit was
/// taken concurrently (`unit_unavailable`); [notAllowed] = the caller's role/ownership
/// forbids it (`permission_denied` / receptionist / `not_your_lead`).
class HoldException implements Exception {
  final String message;
  final bool conflict;
  final bool notAllowed;

  const HoldException(this.message, {this.conflict = false, this.notAllowed = false});

  factory HoldException.fromPostgrest(PostgrestException e) {
    final m = e.message;
    if (m.contains('unit_unavailable')) {
      return HoldException(m, conflict: true);
    }
    if (m.contains('permission_denied') ||
        m.contains('receptionist') ||
        m.contains('not_your_lead')) {
      return HoldException(m, notAllowed: true);
    }
    return HoldException(m);
  }

  @override
  String toString() => message;
}

/// Story 15.4 — raised when confirming a booking is rejected. [notAllowed] = the
/// caller's tier can't confirm (`forbidden_role`); [stale] = the hold is no longer
/// active or the unit left `hold` (`hold_not_active`/`hold_not_found`/`unit_not_held`);
/// [paymentNotVerified] = the RPC got `p_payment_verified = false` (UI always sends
/// true, so this is a backstop).
class ConfirmException implements Exception {
  final String message;
  final bool notAllowed;
  final bool stale;
  final bool paymentNotVerified;

  const ConfirmException(
    this.message, {
    this.notAllowed = false,
    this.stale = false,
    this.paymentNotVerified = false,
  });

  factory ConfirmException.fromPostgrest(PostgrestException e) {
    final m = e.message;
    if (m.contains('forbidden_role')) return ConfirmException(m, notAllowed: true);
    if (m.contains('payment_not_verified')) {
      return ConfirmException(m, paymentNotVerified: true);
    }
    if (m.contains('hold_not_active') ||
        m.contains('hold_not_found') ||
        m.contains('unit_not_held')) {
      return ConfirmException(m, stale: true);
    }
    return ConfirmException(m);
  }

  @override
  String toString() => message;
}

class InventoryRepository {
  final SupabaseClient _supabase;

  const InventoryRepository(this._supabase);

  /// Units for [projectId] via get_project_units. Ordered floor NULLS LAST, unit_no
  /// by the RPC. Throws [InventoryAccessException] on denial / missing project.
  Future<List<ProjectUnit>> getProjectUnits(String projectId) async {
    try {
      final result = await _supabase.rpc(
        'get_project_units',
        params: {'p_project_id': projectId},
      );
      return (result as List)
          .map((row) => ProjectUnit.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw InventoryAccessException.fromPostgrest(e);
    }
  }

  /// Story 15.2 — place a hold on [unitId] for [leadId] via the CAS hold_unit RPC.
  /// Throws [HoldException] (conflict / notAllowed / generic) on rejection.
  Future<UnitHold> holdUnit(String unitId, String leadId) async {
    try {
      final result = await _supabase.rpc(
        'hold_unit',
        params: {'p_unit_id': unitId, 'p_lead_id': leadId},
      );
      return UnitHold.fromRpc(Map<String, dynamic>.from(result as Map));
    } on PostgrestException catch (e) {
      throw HoldException.fromPostgrest(e);
    }
  }

  /// Story 15.2 — the active (not-yet-released) hold on [unitId], or null. Direct
  /// tenant-scoped read of unit_holds (RLS = tenant isolation) so a held unit's
  /// detail sheet can show the live countdown. Read-only.
  Future<UnitHold?> getActiveHold(String unitId) async {
    final rows = await _supabase
        .from('unit_holds')
        .select('id, unit_id, lead_id, holding_agent_id, expires_at')
        .eq('unit_id', unitId)
        .isFilter('released_at', null)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return UnitHold.fromRow(Map<String, dynamic>.from(list.first as Map));
  }

  /// Story 15.4 — confirm a hold as a booking (hold→sold, lead→sold via the shipped
  /// status seam). Payment attestation is enforced in the UI; we always send true.
  /// Throws [ConfirmException] (notAllowed / stale / paymentNotVerified / generic).
  Future<void> confirmBooking(String holdId) async {
    try {
      await _supabase.rpc(
        'confirm_booking',
        params: {'p_hold_id': holdId, 'p_payment_verified': true},
      );
    } on PostgrestException catch (e) {
      throw ConfirmException.fromPostgrest(e);
    }
  }
}

@riverpod
InventoryRepository inventoryRepository(InventoryRepositoryRef ref) {
  return InventoryRepository(Supabase.instance.client);
}
