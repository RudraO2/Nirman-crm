// Story 12.6-mobile — team providers.
//
// teamLeadsProvider is a pure fetch through get_team_leads (authoritative scope).
// ownerNamesProvider derives the bounded owner-id set from the returned leads and
// resolves just those names — fail-soft to an empty map so it never blocks the list.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/models/team_lead.dart';
import '../data/team_repository.dart';

part 'team_providers.g.dart';

/// Leads in the caller's visibility scope. Invalidate to refetch.
@riverpod
Future<List<TeamLead>> teamLeads(TeamLeadsRef ref) {
  return ref.watch(teamRepositoryProvider).getTeamLeads();
}

/// id→display-name for ONLY the owners appearing in [teamLeads]. Empty map on
/// error (owner chip falls back to a masked label).
@riverpod
Future<Map<String, String>> ownerNames(OwnerNamesRef ref) async {
  final leads = await ref.watch(teamLeadsProvider.future);
  final ids = distinctOwnerIds(leads);
  // ref.read (not watch) for the repo — it's stable, and this is past an await.
  return ref.read(teamRepositoryProvider).fetchOwnerNames(ids);
}
