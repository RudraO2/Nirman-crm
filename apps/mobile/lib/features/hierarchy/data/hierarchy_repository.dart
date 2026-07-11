// Story 12.4-mobile — hierarchy data access.
//
// Wraps the shipped set_user_hierarchy RPC (migration 0059) + the tenant-scoped
// `users` / `agencies` table reads that the admin /hierarchy page uses. The RPC is
// authoritative: it re-checks role='admin' and every hierarchy rule server-side, so
// this client never mutates `users` directly and never trusts a client-read role_tier.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/agency.dart';
import 'models/hierarchy_user.dart';

part 'hierarchy_repository.g.dart';

/// Raised when a hierarchy read/write is rejected. [permissionDenied] = caller is
/// not a builder-head (the RPC / RLS raise 42501). Everything else maps a specific
/// RPC guard token to a calm [friendly] message so the UI never shows a raw dump.
class HierarchyException implements Exception {
  final String message;
  final bool permissionDenied;

  const HierarchyException(this.message, {this.permissionDenied = false});

  /// Maps the RPC's RAISEd tokens (surfaced as PostgrestException.message) to a
  /// typed failure. Tokens are the bare strings from 0059 / the agencies RLS.
  factory HierarchyException.fromPostgrest(PostgrestException e) {
    final m = e.message;
    if (m.contains('permission_denied') || m.contains('not_authenticated')) {
      return HierarchyException(m, permissionDenied: true);
    }
    return HierarchyException(m);
  }

  /// A calm, human sentence for the sheet's inline error row.
  String get friendly {
    final m = message;
    if (permissionDenied) {
      return 'Only a builder-head can change the hierarchy.';
    }
    if (m.contains('reporting_cycle_detected')) {
      return 'That would create a reporting loop. Pick a different manager.';
    }
    if (m.contains('reports_to_must_be_higher_tier')) {
      return 'A manager must be a higher tier than this user.';
    }
    if (m.contains('off_ladder_tier_has_no_reports_to')) {
      return 'Partner and Reception users don\'t report to anyone internal.';
    }
    if (m.contains('cannot_report_to_self')) {
      return 'A user can\'t report to themselves.';
    }
    if (m.contains('agency_required_for_partner')) {
      return 'Choose an agency for this partner user.';
    }
    if (m.contains('agency_not_found')) {
      return 'That agency no longer exists. Refresh and try again.';
    }
    if (m.contains('user_not_found')) {
      return 'This user is no longer in your organisation.';
    }
    return 'Couldn\'t save the change. Please try again.';
  }

  @override
  String toString() => message;
}

class HierarchyRepository {
  final SupabaseClient _supabase;

  const HierarchyRepository(this._supabase);

  /// Active tenant users, ordered by name (RLS scopes to tenant; admin may read
  /// all). Mirrors the admin `page.tsx` select.
  Future<List<HierarchyUser>> fetchUsers() async {
    final rows = await _supabase
        .from('users')
        .select(
            'id, email_or_username, role, role_tier, reports_to_user_id, agency_id, is_external, is_active')
        .eq('is_active', true)
        .order('email_or_username');
    return (rows as List)
        .map((r) => HierarchyUser.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Tenant partner agencies (id, name), ordered by name.
  Future<List<Agency>> fetchAgencies() async {
    final rows = await _supabase
        .from('agencies')
        .select('id, name')
        .order('name');
    return (rows as List)
        .map((r) => Agency.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Set [userId]'s tier + reporting line via set_user_hierarchy. [reportsTo] and
  /// [agencyId] must already be nulled by the caller for the tiers that forbid
  /// them (the RPC enforces this too). Throws [HierarchyException] on rejection.
  Future<void> setHierarchy({
    required String userId,
    required RoleTier tier,
    String? reportsTo,
    String? agencyId,
  }) async {
    try {
      await _supabase.rpc('set_user_hierarchy', params: {
        'p_user_id': userId,
        'p_role_tier': tier.dbValue,
        'p_reports_to': reportsTo,
        'p_agency_id': agencyId,
      });
    } on PostgrestException catch (e) {
      throw HierarchyException.fromPostgrest(e);
    }
  }

  /// Create a partner agency. `tenant_id` has no column default and the RLS
  /// WITH CHECK requires it == the caller's tenant, so pass it explicitly from the
  /// session (same as the admin insert). Throws [HierarchyException] on rejection.
  Future<void> createAgency(String name) async {
    final tenantId =
        _supabase.auth.currentSession?.user.appMetadata['tenant_id'] as String?;
    if (tenantId == null) {
      throw const HierarchyException('tenant_missing', permissionDenied: true);
    }
    try {
      await _supabase
          .from('agencies')
          .insert({'name': name.trim(), 'tenant_id': tenantId});
    } on PostgrestException catch (e) {
      throw HierarchyException.fromPostgrest(e);
    }
  }
}

@riverpod
HierarchyRepository hierarchyRepository(HierarchyRepositoryRef ref) {
  return HierarchyRepository(Supabase.instance.client);
}
