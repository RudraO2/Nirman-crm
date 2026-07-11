// Story 14.3-mobile — inventory providers.
//
// projectUnitsProvider is a PURE fetch (family keyed on projectId). Realtime is
// deliberately NOT wired here: the grid screen owns the `units` channel lifecycle
// (tied to the widget) and simply `ref.invalidate`s this provider on a debounced
// event, so the refetch always flows back through the authoritative RPC.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/inventory_repository.dart';
import '../data/models/unit_hold_model.dart';
import '../data/models/unit_model.dart';

part 'inventory_providers.g.dart';

/// Units for [projectId] via get_project_units. Invalidate to refetch (the grid
/// screen does this on Realtime `units` changes).
@riverpod
Future<List<ProjectUnit>> projectUnits(ProjectUnitsRef ref, String projectId) {
  return ref.watch(inventoryRepositoryProvider).getProjectUnits(projectId);
}

/// Story 15.2 — the active hold on [unitId] (null if none). Drives the countdown on
/// a held unit's detail sheet. Invalidate after placing a hold.
@riverpod
Future<UnitHold?> activeHold(ActiveHoldRef ref, String unitId) {
  return ref.watch(inventoryRepositoryProvider).getActiveHold(unitId);
}
