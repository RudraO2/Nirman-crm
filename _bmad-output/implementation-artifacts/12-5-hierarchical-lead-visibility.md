# Story 12.5: hierarchical lead visibility for leaders and heads

Status: review  (migration 0060 written + self-reviewed; mobile leader view deferred; apply deferred)

## Story

As a Team Leader,
I want to see my own leads plus my whole team's leads,
so that I can monitor and coach without losing rep-level isolation.

## Acceptance Criteria

1. **Given** helper `public.visible_user_ids()` (self for reps; recursive subtree for leaders; whole internal tree for heads; agency-only for partners) **When** a `team_leader` calls `get_team_leads` **Then** it returns leads where `assigned_to_user_id IN (SELECT user_id FROM visible_user_ids())`.
2. **And** a `front_line_rep` calling `get_my_leads` (UNCHANGED) still sees only their own leads.
3. **And** a `builder_head` sees all internal leads (existing admin breadth preserved).
4. **And** the recursive subtree query uses `users_reports_to_idx`.
5. **And** a test confirms a leader of team A cannot see team B's leads.

## Tasks / Subtasks

- [ ] **Task 1 — Migration `0057y_visibility.sql`**: `visible_user_ids()` per arch §2.2 (STABLE SECURITY DEFINER, `WITH RECURSIVE` subtree). GRANT EXECUTE authenticated.
- [ ] **Task 2 — `get_team_leads` RPC**: clone the SELECT/decrypt shape of `get_my_leads` (`0017`/`0027`) but scope `assigned_to_user_id IN (SELECT user_id FROM visible_user_ids())`. Same PII decrypt via vault `lead_pii_key`, same urgency sort. Reuse, don't reinvent.
- [ ] **Task 3 — DO NOT touch `get_my_leads`** (AC 2) — reps keep the existing fn verbatim.
- [ ] **Task 4 — Apply + tests** (AC 5): leader sees own+subtree; cross-team isolation; head sees all; partner agency-only.
- [ ] **Task 5 — Mobile**: leader home calls `get_team_leads` when `auth_role_tier()='team_leader'`; rep path unchanged. Add a "Team" toggle/section. `flutter analyze` 0 err.

## Dev Notes

- `visible_user_ids()` is the ONE new visibility primitive — everything tier-scoped (15.5 booking dashboard, etc.) consumes it. [Source: architecture-builder-ops-v2.md §2.2]
- Partners are external — `visible_user_ids()` returns their agency's users only; they must never see internal leads (enforced again at RLS in 12.6). [Source: §13.2]
- `get_my_leads` current: `0017_get_my_leads.sql` + `0027` (name ambiguity fix). Mirror its decrypt/sort exactly in `get_team_leads` to avoid divergence. [Source: 0017, 0027]
- Bound recursion; index `users_reports_to_idx` from 12.1.
- Migration sequential. Mobile touched → `flutter analyze` + run `build_runner` if providers added.

## References
- [Source: epics.md#Story 12.5]
- [Source: architecture-builder-ops-v2.md §2.2 visible_user_ids, §13.2]
- [Source: 0017_get_my_leads.sql, 0027_fix_get_my_leads_name_ambiguity.sql]

## Implementation (2026-06-27)

**File:** `nirman-crm/supabase/migrations/0060_visibility.sql`

- `visible_user_ids()` STABLE SECURITY DEFINER: head/super → whole internal tree (`is_external=false`); partner_agency → own `agency_id` set; team_leader → upward... no, **downward** recursive subtree (`reports_to_user_id` chain); rep/receptionist → self. Fail-closed on missing context. REVOKE PUBLIC/anon, GRANT authenticated+service_role.
- `get_team_leads(limit,offset)` = the latest `get_my_leads` body (0027) reproduced verbatim, changing ONLY `WHERE assigned_to_user_id = auth.uid()` → `IN (SELECT user_id FROM visible_user_ids())`, plus `assigned_to_user_id` surfaced in the output so a leader sees each lead's owner. Identical urgency scoring, PII decrypt, ordering.
- **`get_my_leads` is NOT touched** — reps keep exact FR-18 behaviour.

**Self-review:** nested SECURITY DEFINER (get_team_leads → visible_user_ids) preserves `auth.uid()`/`auth.jwt()` at session level (same pattern as 0016). Partner with NULL agency → `agency_id = NULL` yields empty set (safe). Leaders see team PII by design (coaching). Subtree recursion bounded by `users_reports_to_idx` (0057).

**Deferred:** mobile leader "Team" view calling `get_team_leads` when `auth_role_tier()='team_leader'`. Runtime tests (cross-team isolation, head-all, partner-agency) at apply.

**Status:** backend code-complete, awaiting apply + mobile view.
