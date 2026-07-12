// Progressive disclosure (ux-progressive-disclosure.md §1/§3) — the one canonical
// tenant-usage signal for the You-tab WORKSPACE gates.
//
// tenant_uses_inventory() (0115) is server-truth and one-way: true once the tenant
// has EVER created a project, never reverts. Availability, Booking dashboard and
// Amendments hang off it — absent, not present-and-empty, for a leads-only tenant.
//
// Caching mirrors the one-way contract: only a clean TRUE is final (kept for the
// whole session — no refetch flicker). FALSE is provisional — the admin can create
// the first project on the web at any moment, and the spec requires mobile to
// agree without a logout/reinstall — so it re-checks once a minute while listened.
// Errors fail OPEN (true, also provisional), deliberately the opposite of
// isExecutionMember's fail-soft-false: a transient network error must never make
// earned rows vanish; a new tenant briefly seeing Availability on an error is
// exactly today's (pre-gate) behavior. Screens behind the rows re-guard server-side.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../inventory/data/inventory_repository.dart';

part 'workspace_providers.g.dart';

/// True once the caller's tenant has ever created a project (one-way, server-truth).
@Riverpod(keepAlive: true)
Future<bool> tenantUsesInventory(TenantUsesInventoryRef ref) async {
  bool value;
  bool provisional;
  try {
    value = await ref.watch(inventoryRepositoryProvider).tenantUsesInventory();
    provisional = !value; // false can flip to true under us; true is forever
  } catch (_) {
    value = true; // fail-open — see header comment
    provisional = true;
  }
  if (provisional) {
    final timer = Timer(const Duration(seconds: 60), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return value;
}
