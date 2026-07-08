# Story 14.5: inventory-change auto-notify and held-unit protection

Status: review  (migration 0074 written + applied + smoke ALL PASS 2026-06-28; FCM dispatch wiring + UI deferred; end-to-end hold→available verified after Epic 15)

## Implementation (2026-06-28)

**File:** `nirman-crm/supabase/migrations/0074_inventory_change_guard.sql`

- `update_unit_listing(...)` — builder_head reprice/edit; **rejects hold|sold units** (`unit_locked_release_first`) — the 14↔15 race guard (AC2). `FOR UPDATE` row lock.
- `change_unit_inventory_state(unit, action, expected_version)` — builder_head transitions 14 owns: `withdraw` (available→blocked; held/sold → `unit_locked_release_first`), `restock` (blocked→available), `force_release` (hold|sold→available override). State-machine validated (`invalid_transition`/`invalid_action`); optimistic CAS on `status_version` (`unit_version_conflict`); bumps version.
- `emit_inventory_changed(unit, kind)` — `domain_events('inventory_changed')` producer, **margin-free payload** (AC3). Fired on →available (restock=`new_stock`, force_release=`release`); **Epic 15 release/expire reuse it** so natural hold→available notifies (AC1, end-to-end verified once 15 lands).

**Tested (local runtime):** withdraw available→blocked (v1); reprice held → unit_locked_release_first; withdraw held → unit_locked_release_first; force_release held→available +1 event; restock blocked→available +1 event; non-head denied; CAS mismatch → unit_version_conflict; reprice available ok.

**Deferred:** `inventory_changed` FCM dispatcher edge fn + sales-team deep-link to grid; admin inventory-management UI (withdraw/restock/reprice buttons). New-inventory-insert notify on bulk grid create (currently notifies on restock; bulk-add producer is a small follow-on).

## Story

As a salesperson,
I want to be notified when inventory I care about changes,
so that I act on releases and new stock quickly.

## Acceptance Criteria

1. **Given** a unit status transition **When** a hold is released (hold→available) or new inventory is added **Then** a notification is enqueued (reusing the dispatcher) deep-linking to the availability grid.
2. **And** a developer update cannot withdraw/reprice a unit currently `hold` or `sold` without a Builder Head releasing it first.
3. **And** notifications respect partner visibility rules (no margin, agency-scoped).

## Tasks / Subtasks

- [ ] **Task 1 — Notify on transition**: trigger or in-RPC enqueue on `units` status change to `available` (release) and on new-inventory insert → `pending_notifications` to the project's sales team. (The `hold→available` events are produced by Epic 15 release/expire; wire the producer here, events flow once 15 lands.)
- [ ] **Task 2 — Held/sold withdraw guard**: the edit-inventory / reprice / developer-update-withdraw path must reject changing a unit that is `hold` or `sold` unless a `builder_head` releases it first (raise `unit_locked_release_first`).
- [ ] **Task 3 — Tests**: release notifies; new stock notifies; cannot reprice/withdraw a held/sold unit without head release; partner notifications carry no margin.

## Dev Notes

- Resolves the 14↔15 runtime race (broadcast can't invalidate a live hold). [Source: architecture-builder-ops-v2.md §13.3, Mary party review]
- Cross-epic: the `hold→available` events come from Epic 15 (15.2 release / 15.3 expire). 14.5 owns the notify-rule + withdraw-guard; verify end-to-end after 15 lands. [Source: epics.md 14.5 sequencing note]
- Reuse dispatcher (no new transport).

## References
- [Source: epics.md#Story 14.5; architecture-builder-ops-v2.md §13.3]

> **0084 hardening (2026-06-28 review):** force_release now releases the active hold row (orphan-hold fix). See builder-ops-backend-review-2026-06-28.md.
