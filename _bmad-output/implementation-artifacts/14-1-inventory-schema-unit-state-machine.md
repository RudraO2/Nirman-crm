# Story 14.1: inventory schema and unit state machine

Status: review  (migration 0070 written + applied to local stack + RLS/structural smoke ALL PASS 2026-06-28)

## Implementation (2026-06-28)

**File:** `nirman-crm/supabase/migrations/0070_inventory.sql` (planned "0058" in epics.md; real next number is 0070 — Epic 12-13 took 0057-0069).

- `projects.hold_timer_hours int` (nullable; required at grid creation 14.2, no global default).
- `unit_status` enum `(available, hold, sold, blocked)` (guarded CREATE).
- `towers` (tenant_id, project_id, name uniq, sort_order) + `units` (unit_no, floor, configuration, carpet_area_sqft, status, list_price_paise, cost_paise[margin], status_version[CAS token]). FK→tenants/projects/towers. Unique index `(tenant_id, project_id, COALESCE(tower_id, nil-uuid), unit_no)`; index `(tenant_id, project_id, status)`; FK indexes. ENABLE+FORCE RLS + `FOR ALL ... tenant_id = auth_tenant_id()` policy (mirror 0009); GRANTs; `set_updated_at` triggers.
- **Canonical state machine documented in the 0070 header** — single source for Epic 15 holds + Epic 16 amendments: `available→hold→sold`, `hold→available`, `available↔blocked` (head), `sold→available` (head override). hold/sold can't be withdrawn without builder_head.

**Tested (local Docker stack, runtime):** AC1 hold_timer_hours present; AC2 all 8 unit cols; AC3 enum 4 values; AC5 duplicate unit_no rejected (unique_violation); AC6 RLS cross-tenant = 0 rows, own-tenant = 1. All pass.

**Deferred:** TS type regen + admin-web/mobile inventory UI (lands with 14.3 read path).

## Story

As a developer,
I want the tower/unit schema with one documented status lifecycle,
so that holds (Epic 15) and amendments (Epic 16) share one definition of legal transitions.

## Acceptance Criteria

1. **Given** migration `0058_inventory.sql` **When** applied **Then** `public.projects` gains `hold_timer_hours int`; tables `towers` and `units` exist with `tenant_id` + `ENABLE`/`FORCE` RLS (standard `auth_tenant_id()` policy).
2. **And** `units` carries `unit_no, floor, configuration, carpet_area_sqft, status (unit_status enum), list_price_paise, cost_paise, status_version int`.
3. **And** enum `unit_status = (available, hold, sold, blocked)` exists.
4. **And** the canonical state machine is documented in the migration header: `available→hold→sold`, `hold→available`, `available↔blocked` (head), `sold→available` (head override only).
5. **And** uniqueness prevents duplicate `unit_no` within a project/tower.
6. **And** an RLS smoke test confirms cross-tenant queries return 0 rows.

## Tasks / Subtasks

- [ ] **Task 1 — Migration `0058`**: `ALTER TABLE projects ADD COLUMN hold_timer_hours int`; `CREATE TYPE unit_status`; `CREATE TABLE towers`, `CREATE TABLE units` (cols per AC2) with FK→projects/towers, `tenant_id`→tenants; unique `(tenant_id, project_id, COALESCE(tower_id,'00..0'::uuid), unit_no)`; index `(tenant_id, project_id, status)`; `ENABLE`+`FORCE` RLS + tenant policy on both; GRANTs.
- [ ] **Task 2 — State machine comment**: enumerate legal transitions in header (the single source consumed by 15/16).
- [ ] **Task 3 — Apply** via `db push --linked`; RLS smoke test for towers + units.
- [ ] **Task 4 — Types**: regenerate TS types.

## Dev Notes

- Mirror RLS+FORCE+policy shape from `0009`. `cost_paise` is the margin column — never selected by non-`builder_head` read paths (14.3/12.6). [Source: architecture-builder-ops-v2.md §3.1, §13.2]
- `status_version` is the optimistic-concurrency token for the CAS hold (15.2). [Source: §4.2]
- Per-project `hold_timer_hours` (no global default) — required at grid creation (14.2). [Source: §1.3 hold-timer]
- Prices in paise (consistent with `leads.budget_min`). [Source: 0009 budget_min comment]
- Migration target `0058` per arch; confirm `migration list` head.

## References
- [Source: epics.md#Story 14.1; architecture-builder-ops-v2.md §3.1, §13.3 state machine]
- [Source: 0008_create_projects.sql, 0009 RLS shape]
