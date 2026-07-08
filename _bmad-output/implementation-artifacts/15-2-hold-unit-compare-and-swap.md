# Story 15.2: hold a unit via compare-and-swap

Status: review  (migration 0076 written + applied + guards 6/6 + REAL parallel race ALL PASS 2026-06-28)

## Implementation (2026-06-28)

**File:** `nirman-crm/supabase/migrations/0076_hold_unit.sql`

- `hold_unit(p_unit_id, p_lead_id)` SECURITY DEFINER. **Two stacked guards:** (1) CAS `UPDATE units SET status='hold', status_version+1 WHERE id=? AND status='available' RETURNING` — unit row lock serializes; loser gets 0 rows → `unit_unavailable` (ERRCODE 42501, not 23505/500); (2) `unit_holds_one_active_idx` partial unique — INSERT `unique_violation` caught + remapped to `unit_unavailable`.
- Winner gets `unit_holds` row with `expires_at = now() + hold_timer_hours` + `carpet_area_sqft` snapshot; `unit_held` timeline event logged (new enum value, bare ADD VALUE).
- **`tenants.require_verified_before_hold`** flag added (default OFF) — when ON, requires lead `visit_count > 0`.
- Ownership: front_line_rep/partner_agency → own leads only; team_leader → `visible_user_ids()` subtree; builder_head → any tenant lead; receptionist → denied.

**Tested (local runtime):**
- Guards (rollback txn): hold success → unit=hold; re-hold → unit_unavailable; unit_held event logged (1); foreign-lead → not_your_lead; receptionist → permission_denied; require_verified ON + visit_count 0 → hold_requires_verified_visit.
- **Concurrency (two parallel connections, committed):** exactly one winner (hold_id, v1); loser `unit_unavailable` (no 23505 bubble); unit ends `hold`, active_holds=1. AC5 ✅.

**Deferred:** mobile/admin Hold action + amber-tile Realtime transition.

## Story

As a salesperson,
I want to place a hold on an available unit for my lead,
so that I lock it while the customer decides — without race conditions.

## Acceptance Criteria

1. **Given** `hold_unit(p_unit_id, p_lead_id)` **When** two agents attempt to hold the same available unit concurrently **Then** the CAS `UPDATE units SET status='hold', status_version=status_version+1 WHERE id=? AND status='available' RETURNING` lets exactly one win; the loser gets a clean `unit_unavailable` (not 23505→500).
2. **And** the winner gets a `unit_holds` row with `expires_at = held_at + (project.hold_timer_hours)` + `carpet_area_sqft` snapshot.
3. **And** a `unit_held` Timeline event is logged on the lead.
4. **And** if the tenant `require_verified_before_hold` flag is ON, the hold is rejected unless the lead's `visit_count > 0` (flag default OFF).
5. **And** a concurrency test asserts exactly one of two simultaneous holds succeeds and the unit ends in `hold`.

## Tasks / Subtasks

- [ ] **Task 1 — `hold_unit` RPC** (SECURITY DEFINER) per arch §4.2: CAS update on units; on 0 rows → raise `unit_unavailable` (42501/409 mapping); read `project.hold_timer_hours`; INSERT unit_holds (partial-unique index = 2nd concurrent insert fails cleanly); log `unit_held`.
- [ ] **Task 2 — require_verified flag**: tenant config flag (default OFF); when ON, check `visit_count > 0` before CAS.
- [ ] **Task 3 — Capability**: partner may hold OWN-lead units only; reps/leaders/head may hold. Receptionist cannot.
- [ ] **Task 4 — Mobile/admin**: "Hold" action on unit detail (from 14.3 grid) with lead picker; tile flips to amber on success (Realtime).
- [ ] **Task 5 — Concurrency tests**: two parallel holds → exactly one wins, clean rejection for loser, unit ends `hold`; 23505 never bubbles as 500.

## Dev Notes

- Two stacked guards: the `WHERE status='available'` CAS AND the `unit_holds_one_active_idx` partial unique. Exactly one winner; no locks held across think-time. [Source: architecture-builder-ops-v2.md §4.2, Amelia]
- Catch `unique_violation` from the holds insert and map to `unit_unavailable` (don't let it 500). [Source: Amelia party review]
- `require_verified_before_hold` default OFF keeps 15 independent of 13 (pitch). [Source: §13.6]
- **Demo centerpiece** with 14.3 — polish the amber-tile transition.

## References
- [Source: epics.md#Story 15.2; architecture-builder-ops-v2.md §4.2, §13.6]

> **0084 hardening (2026-06-28 review):** partner holds gated to agency-shared projects. See builder-ops-backend-review-2026-06-28.md.
