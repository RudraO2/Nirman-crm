// Story 16.2-mobile — amendments data access.
//
// Wraps the shipped log_amendment (0081/0084), get_amendments_for_execution +
// set_amendment_status + add_execution_member (0082). The RPCs are authoritative:
// they enforce tier/visibility/link on log, and membership + lifecycle on the
// execution surface. This client renders exactly what they return + maps their
// RAISEd tokens to calm messages. No lead PII crosses the execution surface.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/execution_amendment.dart';

part 'amendments_repository.g.dart';

/// Raised when log_amendment is rejected. Each flag drives a calm inline message.
class LogAmendmentException implements Exception {
  final String message;
  final bool forbidden; // partner_agency / not_authenticated
  final bool notAmendable; // unit not hold/sold
  final bool notVisible; // lead outside visibility
  final bool notLinked; // lead doesn't hold/own the unit (0084)
  final bool notFound; // unit_not_found / lead_not_found
  final bool descriptionRequired;

  const LogAmendmentException(
    this.message, {
    this.forbidden = false,
    this.notAmendable = false,
    this.notVisible = false,
    this.notLinked = false,
    this.notFound = false,
    this.descriptionRequired = false,
  });

  factory LogAmendmentException.fromPostgrest(PostgrestException e) {
    final m = e.message;
    if (m.contains('forbidden_role') || m.contains('not_authenticated')) {
      return LogAmendmentException(m, forbidden: true);
    }
    if (m.contains('unit_not_amendable')) {
      return LogAmendmentException(m, notAmendable: true);
    }
    if (m.contains('lead_not_linked_to_unit')) {
      return LogAmendmentException(m, notLinked: true);
    }
    if (m.contains('lead_not_visible')) {
      return LogAmendmentException(m, notVisible: true);
    }
    if (m.contains('unit_not_found') || m.contains('lead_not_found')) {
      return LogAmendmentException(m, notFound: true);
    }
    if (m.contains('description_required')) {
      return LogAmendmentException(m, descriptionRequired: true);
    }
    return LogAmendmentException(m);
  }

  String get friendly {
    if (descriptionRequired) return 'Add a short description of the change.';
    if (forbidden) return "You can't log amendments.";
    if (notAmendable) return 'Amendments are only for held or sold units.';
    if (notLinked) return "This lead doesn't hold or own that unit.";
    if (notVisible) return 'That lead is outside your visibility.';
    if (notFound) return 'That unit or lead no longer exists.';
    return "Couldn't log the amendment. Try again.";
  }

  @override
  String toString() => message;
}

/// Raised on the execution surface (read / status change / join).
class ExecutionException implements Exception {
  final String message;
  final bool notMember;
  final bool invalidTransition;
  final bool notFound;
  final bool notHead;

  const ExecutionException(
    this.message, {
    this.notMember = false,
    this.invalidTransition = false,
    this.notFound = false,
    this.notHead = false,
  });

  factory ExecutionException.fromPostgrest(PostgrestException e) {
    final m = e.message;
    if (m.contains('not_execution_member')) {
      return ExecutionException(m, notMember: true);
    }
    if (m.contains('invalid_transition')) {
      return ExecutionException(m, invalidTransition: true);
    }
    if (m.contains('amendment_not_found') || m.contains('user_not_found')) {
      return ExecutionException(m, notFound: true);
    }
    if (m.contains('permission_denied')) {
      return ExecutionException(m, notHead: true);
    }
    return ExecutionException(m);
  }

  String get friendly {
    if (notMember) return "You're not on the execution team.";
    if (invalidTransition) return "That status change isn't allowed.";
    if (notHead) return 'Only a Builder Head can do that.';
    if (notFound) return 'That record no longer exists.';
    return "Something went wrong. Pull to refresh.";
  }

  @override
  String toString() => message;
}

class AmendmentsRepository {
  final SupabaseClient _supabase;

  const AmendmentsRepository(this._supabase);

  /// Log an amendment against a held/sold unit for its linked lead. Returns the new
  /// amendment id. Throws [LogAmendmentException] on any guard rejection.
  Future<String> logAmendment({
    required String unitId,
    required String leadId,
    required String description,
  }) async {
    try {
      final id = await _supabase.rpc('log_amendment', params: {
        'p_unit_id': unitId,
        'p_lead_id': leadId,
        'p_description': description.trim(),
      });
      return id as String;
    } on PostgrestException catch (e) {
      throw LogAmendmentException.fromPostgrest(e);
    }
  }

  /// Execution-team surface (member-gated, PII-minimized). Optional [status] filter.
  /// Throws [ExecutionException] (notMember) when the caller isn't on the team.
  Future<List<ExecutionAmendment>> getAmendmentsForExecution({
    AmendmentStatus? status,
  }) async {
    try {
      final rows = await _supabase.rpc('get_amendments_for_execution', params: {
        'p_status': status?.dbValue,
      });
      return (rows as List)
          .map((r) =>
              ExecutionAmendment.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw ExecutionException.fromPostgrest(e);
    }
  }

  /// Move an amendment through its lifecycle. Throws [ExecutionException]
  /// (notMember / invalidTransition / notFound) on rejection.
  Future<void> setAmendmentStatus({
    required String amendmentId,
    required AmendmentStatus newStatus,
  }) async {
    try {
      await _supabase.rpc('set_amendment_status', params: {
        'p_amendment_id': amendmentId,
        'p_new_status': newStatus.dbValue,
      });
    } on PostgrestException catch (e) {
      throw ExecutionException.fromPostgrest(e);
    }
  }

  /// Builder-head adds [userId] to the execution team. Throws [ExecutionException]
  /// (notHead) if the caller isn't a head.
  Future<void> joinExecutionTeam(String userId) async {
    try {
      await _supabase.rpc('add_execution_member', params: {'p_user_id': userId});
    } on PostgrestException catch (e) {
      throw ExecutionException.fromPostgrest(e);
    }
  }

  /// Whether the caller is on the tenant's execution team. A cheap tenant-scoped
  /// read of tenant_execution_team (its SELECT policy = any tenant member) so the
  /// You-tab can surface the Amendments entry to a NON-head member — membership is a
  /// table row, not a JWT claim, so the cosmetic role gate alone would hide it.
  /// Fail-soft: any error → false (the entry stays hidden; the screen re-guards).
  Future<bool> isExecutionMember() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      final rows = await _supabase
          .from('tenant_execution_team')
          .select('user_id')
          .eq('user_id', uid)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

@riverpod
AmendmentsRepository amendmentsRepository(AmendmentsRepositoryRef ref) {
  return AmendmentsRepository(Supabase.instance.client);
}
