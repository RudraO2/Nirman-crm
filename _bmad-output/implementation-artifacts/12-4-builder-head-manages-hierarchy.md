# Story 12.4: builder head manages the reporting hierarchy

Status: review  (migration 0059 + manage-employee block written + self-reviewed; web UI deferred. 2026-07-12 audit note: "live apply deferred" was stale — 0059 has been ON PROD since 2026-07-07; mobile UI slice committed dbe2ee6)

## Story

As a Builder Head,
I want to create team leaders and assign reps under them,
so that the org tree reflects real reporting lines.

## Acceptance Criteria

1. **Given** I am `builder_head` **When** I create/edit a user with a `role_tier` + optional `reports_to_user_id` **Then** the RPC enforces `reports_to_user_id` points to a strictly higher tier in the same tenant (rep→leader, leader→head).
2. **And** a cycle in the reporting tree is rejected with a clear error.
3. **And** a `partner_agency` user requires an `agency_id` and is set `is_external = true`.
4. **And** deactivating a leader who has reports is blocked until reports are re-parented (mirrors FR-32).
5. **And** each change appends a `user_events` audit entry (existing pattern).
6. **And** the RPC is admin-only (`auth_role_tier()='builder_head'`, equivalently `role='admin'`).

## Tasks / Subtasks

- [ ] **Task 1 — Migration `0057x_hierarchy_mgmt_rpcs.sql`**: `set_user_hierarchy(p_user_id, p_role_tier, p_reports_to, p_agency_id)` SECURITY DEFINER:
  - [ ] Guard `auth_role_tier()='builder_head'` (or `role='admin'`); tenant via `auth_tenant_id()`.
  - [ ] Validate `reports_to` tier strictly higher (tier rank map: super>head>leader>rep; partner/receptionist off-ladder → reports_to NULL or head).
  - [ ] Cycle check via recursive walk up `reports_to` — reject if `p_user_id` reachable.
  - [ ] If `p_role_tier='partner_agency'`: require `p_agency_id` present + same tenant; set `is_external=true`. Else `is_external=false`.
  - [ ] Append `user_events` row (existing audit table from `0004`).
- [ ] **Task 2 — Block leader deactivation with reports**: extend existing deactivate path (Story 1.6 / `0001` users) to check `EXISTS reports_to_user_id = target` → raise `has_reports_reparent_first` (mirror FR-32 reassignment block).
- [ ] **Task 3 — Apply + tests**: cycle rejected; rep→head (skip leader) rejected; partner without agency rejected; deactivate-with-reports blocked.
- [ ] **Task 4 — Admin web UI** (`apps/admin`): team page gains tier + reports-to selectors (reuse existing /team page from Story 1.3/1.6). Guard `role='admin'`.

## Dev Notes

- Tier-rank helper: encode an ordering so "strictly higher" is checkable. Partner/receptionist are off the sales ladder — partner reports to nobody internal; receptionist likewise. Document the rule.
- Reuse `user_events` audit (migration `0004_create_user_events.sql`). [Source: 0004]
- Deactivation block mirrors Story 4.5 lead-reassignment pattern. [Source: epics.md FR-32; 4-5 story]
- Migration sequential after 12.1/12.2. No mobile (admin web only) → `flutter analyze` N/A; run web typecheck/lint.

## References
- [Source: epics.md#Story 12.4]
- [Source: architecture-builder-ops-v2.md §2.1 constraints, §13.1]
- [Source: 0001 users + deactivate, 0004 user_events]

## Implementation (2026-06-27)

**Files:** `nirman-crm/supabase/migrations/0059_hierarchy_mgmt.sql` · edited `supabase/functions/manage-employee/index.ts`.

- `0059`: `ALTER TYPE user_event_type ADD VALUE IF NOT EXISTS 'hierarchy_changed'` (bare, before the txn block — new label committed before use); `role_tier_rank(role_tier)` IMMUTABLE; `set_user_hierarchy(user, tier, reports_to, agency)` SECURITY DEFINER admin-only: `FOR UPDATE` on target, agency-required-for-partner (+is_external=true), off-ladder (partner/receptionist) forced no reports_to, strictly-higher-tier check via `role_tier_rank`, **cycle reject via upward recursive CTE** (p_user_id ancestor of p_reports_to ⇒ reject), audit to `user_events`. REVOKE PUBLIC/anon, GRANT authenticated.
- `manage-employee` step 7.5: deactivation blocked if target has ≥1 active direct report (`reports_to_user_id = target, is_active`), `validation_error` — mirrors FR-32 re-parent-first.

**Self-review:** SECURITY DEFINER owner bypasses RLS but tenant scoped explicitly by `auth_tenant_id()`. Changing a user off `partner_agency` clears `agency_id`. ADD VALUE is idempotent. Cycle CTE direction verified (walk up from new parent; if it reaches the user, the edge would close a loop).

**Deferred:** admin-web hierarchy UI (tier + reports-to selectors on /team) — backend complete, UI is part of the extension's web build pass. Runtime tests (cycle/rank/partner/deactivation-block) at apply.

**Status:** backend code-complete, awaiting apply + web UI.
