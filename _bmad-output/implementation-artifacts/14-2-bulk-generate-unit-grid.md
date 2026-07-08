# Story 14.2: bulk-generate a unit grid

Status: review  (migration 0071 written + applied + smoke ALL PASS 2026-06-28)

## Implementation (2026-06-28)

**File:** `nirman-crm/supabase/migrations/0071_generate_unit_grid.sql`

- `generate_unit_grid(p_project_id, p_tower_id, p_floors, p_units_per_floor, p_config_map jsonb, p_hold_timer_hours, p_carpet_area_sqft?, p_list_price_paise?, p_cost_paise?)` → jsonb. SECURITY DEFINER, `builder_head`-only guard, tenant via `auth_tenant_id()`.
- **Set-based** insert (no per-unit loop): `generate_series(floors) × generate_series(units_per_floor)`; `unit_no = (floor*100 + pos)::text`; `configuration = config_map ->> pos`. `config_map` = `{"<pos>":"<config>"}` applied per floor (e.g. pos 1-6 → 2BHK, 7-12 → 3BHK).
- Idempotent via `ON CONFLICT (tenant,project,COALESCE(tower,nil),unit_no) DO NOTHING` (the 0070 unique index). Returns `{created, skipped_existing, attempted, hold_timer_hours}`.
- `hold_timer_hours` REQUIRED (>=1) and persisted on the project (AC2, no global default). Project + tower ownership validated.

**Tested (local runtime, The Velocity 6×12):** created 72; 2BHK=36/3BHK=36/total 72; project hold_timer_hours=24; floor-1 unit_no 101-112; re-run created 0 / skipped 72 (idempotent); front_line_rep denied (42501); NULL hold_timer rejected (hold_timer_required).

**Deferred:** admin-web project-setup grid form (Task 2).

## Story

As a Builder Head,
I want to create a project's units in one action (e.g. 72 units, 12/floor),
so that I don't enter units one by one.

## Acceptance Criteria

1. **Given** I am `builder_head` **When** I call `generate_unit_grid(project, tower, floors, units_per_floor, config_map)` **Then** units are inserted in one transaction with correct `unit_no`/`floor`/`configuration`.
2. **And** the project's `hold_timer_hours` must be set at/with grid creation (no global default).
3. **And** re-running for an existing grid does not duplicate units (idempotent on `unit_no` via the unique constraint).
4. **And** only `builder_head` may call it.

## Tasks / Subtasks

- [ ] **Task 1 — `generate_unit_grid` RPC** (SECURITY DEFINER): guard `auth_role_tier()='builder_head'`; loop floors × units_per_floor; derive `unit_no` (e.g. `floor*100 + n`); apply `config_map` per floor/position; `INSERT ... ON CONFLICT DO NOTHING` (idempotent on unique). Require + persist `hold_timer_hours` on the project.
- [ ] **Task 2 — Admin web**: project setup page → grid generator form (towers, floors, units/floor, config, hold timer). Reuse /settings/projects.
- [ ] **Task 3 — Tests**: 72 units / 12-floor grid created; re-run no dup; non-head denied; missing hold_timer rejected.

## Dev Notes

- `ON CONFLICT DO NOTHING` against the `(tenant_id,project_id,tower_id,unit_no)` unique (14.1) gives idempotency. [Source: 14-1]
- Head-only (tier guard). [Source: architecture-builder-ops-v2.md §13.2 matrix]
- Admin web only.

## References
- [Source: epics.md#Story 14.2; architecture-builder-ops-v2.md §3.1]
