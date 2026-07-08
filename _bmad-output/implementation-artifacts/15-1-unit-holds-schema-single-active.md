# Story 15.1: unit_holds schema with single-active-hold guarantee

Status: review  (migration 0075 written + applied + single-active + RLS smoke ALL PASS 2026-06-28)

## Implementation (2026-06-28)

**File:** `nirman-crm/supabase/migrations/0075_unit_holds.sql` (planned "0059"; real next number 0075).

- `hold_outcome` enum (converted, released, expired, cancelled). `unit_holds(id, tenant_id, unit_id→units CASCADE, lead_id→leads RESTRICT, holding_agent_id→users RESTRICT, carpet_area_sqft, held_at, expires_at, released_at, outcome, created_at)`.
- **Partial UNIQUE `unit_holds_one_active_idx (unit_id) WHERE released_at IS NULL`** = at-most-one-active-hold-per-unit at the DB level (AC2). Expiry-sweep index `(expires_at) WHERE released_at IS NULL` (AC3). FK indexes.
- ENABLE+FORCE RLS + tenant policy; GRANTs.
- **Active-hold invariant `released_at IS NULL` documented in the header** — single source for 15.2 CAS + 15.3 cron (AC4).

**Tested (local runtime):** first active hold inserts; second active hold on same unit → unique_violation (single-active guarantee); after release, a new active hold is accepted (active count stays 1); RLS cross-tenant = 0 rows.

## Story

As a developer,
I want the holds table with a DB-level single-active-hold guarantee,
so that two agents can never hold the same unit.

## Acceptance Criteria

1. **Given** migration `0059_unit_holds.sql` **When** applied **Then** `public.unit_holds(id, tenant_id, unit_id, lead_id, holding_agent_id, carpet_area_sqft, held_at, expires_at, released_at, outcome)` exists with `ENABLE`/`FORCE` RLS.
2. **And** partial unique index `unit_holds_one_active_idx (unit_id) WHERE released_at IS NULL` exists.
3. **And** index `(expires_at) WHERE released_at IS NULL` supports the release sweep.
4. **And** the partial-unique predicate exactly matches the "active hold" definition used by the CAS (15.2) — one invariant, not two drifting ones.

## Tasks / Subtasks

- [ ] **Task 1 — Migration `0059`**: `CREATE TABLE unit_holds` (cols per AC1; FKs unit_id→units, lead_id→leads ON DELETE RESTRICT, holding_agent_id→users); `ENABLE`+`FORCE` RLS + tenant policy; partial unique active-hold index; expiry index. GRANTs.
- [ ] **Task 2 — Apply + RLS smoke** (cross-tenant → 0 rows).
- [ ] **Task 3 — Doc the active-hold invariant** in the header so 15.2/15.3 reference the same definition (`released_at IS NULL`).

## Dev Notes

- `released_at IS NULL` = "active". The CAS (15.2) and the cron (15.3) both key off this exact predicate — keep them identical. [Source: architecture-builder-ops-v2.md §4.1, Amelia party review]
- `lead_id ON DELETE RESTRICT` — a hold must not orphan when a lead row is touched (leads are never deleted anyway, but be explicit).
- Migration `0059` per arch; confirm head via `migration list`.

## References
- [Source: epics.md#Story 15.1; architecture-builder-ops-v2.md §4.1]
