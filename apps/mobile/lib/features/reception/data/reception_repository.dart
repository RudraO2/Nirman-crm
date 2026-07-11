// Story 13.4-mobile — reception data access.
//
// Wraps the shipped verify_visit RPC (migration 0067). The RPC is authoritative:
// it guards the caller's tier (receptionist / builder_head), resolves the code to a
// lead in the caller's tenant, increments visit_count, and logs the timeline events.
// This client only sends the trimmed/uppercased code and renders the returned ordinal
// — it never touches leads / lead_timeline directly, and never reads lead PII here.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/visit_result.dart';

part 'reception_repository.g.dart';

/// Raised when verify_visit is rejected. [notFound] = the code matched no lead in
/// the caller's tenant (`invalid_customer_code`); [notAllowed] = the caller's tier
/// cannot verify (`permission_denied` / `not_authenticated`).
class VerifyVisitException implements Exception {
  final String message;
  final bool notFound;
  final bool notAllowed;

  const VerifyVisitException(
    this.message, {
    this.notFound = false,
    this.notAllowed = false,
  });

  factory VerifyVisitException.fromPostgrest(PostgrestException e) {
    final m = e.message;
    if (m.contains('invalid_customer_code')) {
      return VerifyVisitException(m, notFound: true);
    }
    if (m.contains('permission_denied') || m.contains('not_authenticated')) {
      return VerifyVisitException(m, notAllowed: true);
    }
    return VerifyVisitException(m);
  }

  String get friendly {
    if (notFound) return 'No lead matches that code — check and re-enter.';
    if (notAllowed) return "You don't have access to reception check-in.";
    return "Couldn't verify that code. Try again.";
  }

  @override
  String toString() => message;
}

class ReceptionRepository {
  final SupabaseClient _supabase;

  const ReceptionRepository(this._supabase);

  /// Verify a walk-in by [code] via verify_visit. The code is trimmed + uppercased
  /// client-side to mirror the RPC's `upper(trim(code))` (so `nir-44d77` resolves).
  /// Throws [VerifyVisitException] (notFound / notAllowed / generic) on rejection.
  Future<VisitResult> verifyVisit(String code) async {
    try {
      final result = await _supabase.rpc(
        'verify_visit',
        params: {'p_code': normalizeCode(code)},
      );
      return VisitResult.fromJson(Map<String, dynamic>.from(result as Map));
    } on PostgrestException catch (e) {
      throw VerifyVisitException.fromPostgrest(e);
    }
  }

  /// Pure: trim + uppercase (exported for unit testing).
  static String normalizeCode(String raw) => raw.trim().toUpperCase();
}

@riverpod
ReceptionRepository receptionRepository(ReceptionRepositoryRef ref) {
  return ReceptionRepository(Supabase.instance.client);
}
