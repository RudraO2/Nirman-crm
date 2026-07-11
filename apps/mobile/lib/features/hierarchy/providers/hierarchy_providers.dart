// Story 12.4-mobile — hierarchy providers.
//
// Both are PURE fetches through the authoritative source (the `users` / `agencies`
// reads). After a successful set_user_hierarchy / createAgency the UI invalidates
// the affected provider so the list re-flows through the DB — no optimistic lie
// (same posture as Slice 1's refetch-through-RPC).

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/hierarchy_repository.dart';
import '../data/models/agency.dart';
import '../data/models/hierarchy_user.dart';

part 'hierarchy_providers.g.dart';

/// Active tenant users for the Organization list. Invalidate after an edit.
@riverpod
Future<List<HierarchyUser>> hierarchyUsers(HierarchyUsersRef ref) {
  return ref.watch(hierarchyRepositoryProvider).fetchUsers();
}

/// Tenant partner agencies. Invalidate after creating one.
@riverpod
Future<List<Agency>> agencies(AgenciesRef ref) {
  return ref.watch(hierarchyRepositoryProvider).fetchAgencies();
}
