// Story 12.6-mobile — team data access.
//
// Wraps the shipped get_team_leads RPC (migration 0060). Scope (subtree / all /
// agency-only / self) is enforced server-side by visible_user_ids(); this client
// renders exactly what the RPC returns and never filters leads itself. Owner names
// are resolved only for the ids present in the returned leads (bounded — keeps the
// partner sandbox intact).

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/team_lead.dart';

part 'team_repository.g.dart';

/// Raised when the team-leads read is denied. [notAuthenticated] = no session
/// context (the RPC raises `not_authenticated`). An empty scope is NOT an error —
/// the RPC returns zero rows for a receptionist / self-only rep, which the UI shows
/// as a calm empty state.
class TeamAccessException implements Exception {
  final String message;
  final bool notAuthenticated;

  const TeamAccessException(this.message, {this.notAuthenticated = false});

  factory TeamAccessException.fromPostgrest(PostgrestException e) {
    final m = e.message;
    if (m.contains('not_authenticated')) {
      return TeamAccessException(m, notAuthenticated: true);
    }
    return TeamAccessException(m);
  }

  String get friendly => notAuthenticated
      ? 'Please sign in again to view team leads.'
      : "Couldn't load team leads. Pull to refresh.";

  @override
  String toString() => message;
}

class TeamRepository {
  final SupabaseClient _supabase;

  const TeamRepository(this._supabase);

  /// Leads in the caller's visibility scope via get_team_leads. Throws
  /// [TeamAccessException] on a hard denial (empty scope is a normal empty list).
  Future<List<TeamLead>> getTeamLeads({int limit = 100, int offset = 0}) async {
    try {
      final rows = await _supabase.rpc('get_team_leads', params: {
        'p_limit': limit,
        'p_offset': offset,
      });
      return (rows as List)
          .map((r) => TeamLead.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw TeamAccessException.fromPostgrest(e);
    }
  }

  /// Resolve display names for ONLY the given owner ids (never the whole roster).
  /// Fail-soft: any error yields an empty map so the list still renders (owners fall
  /// back to a masked label).
  Future<Map<String, String>> fetchOwnerNames(Set<String> ownerIds) async {
    if (ownerIds.isEmpty) return const {};
    try {
      final rows = await _supabase
          .from('users')
          .select('id, email_or_username')
          .inFilter('id', ownerIds.toList());
      final map = <String, String>{};
      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);
        map[m['id'] as String] = m['email_or_username'] as String;
      }
      return map;
    } catch (_) {
      return const {};
    }
  }
}

@riverpod
TeamRepository teamRepository(TeamRepositoryRef ref) {
  return TeamRepository(Supabase.instance.client);
}
