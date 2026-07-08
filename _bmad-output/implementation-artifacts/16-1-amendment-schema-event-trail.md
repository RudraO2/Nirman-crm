# Story 16.1: amendment schema with immutable event trail

Status: review  (migration 0080 written + applied + RLS/append-only/admin smoke ALL PASS 2026-06-28)

## Implementation (2026-06-28)

**File:** `nirman-crm/supabase/migrations/0080_amendments.sql` (planned "0065"; real next number 0080).

- `amendment_status` enum (requested, acknowledged, in_progress, done, rejected).
- `amendments` (unit_id→units RESTRICT, lead_id→leads RESTRICT, description, status, logged_by) — RLS+FORCE tenant policy, full CRUD grant, set_updated_at trigger.
- `amendment_events` **append-only** — SELECT-only grant + RLS SELECT policy; the only INSERT path is the SECURITY DEFINER `log_amendment_event(amendment, event_type, from?, to?, note?)` helper (same-tenant enforced when JWT present; system-callable).
- `tenant_execution_team(tenant_id, user_id PK)` — membership (not a tier); SELECT=tenant, INSERT/DELETE admin-only (mirrors agencies/0057).

**Bug caught + fixed by testing:** initial `GRANT SELECT` did NOT make amendment_events append-only — Supabase default privileges grant ALL (incl UPDATE/DELETE) to authenticated/anon on new public tables (lead_timeline shares this; its immutability rests on RLS silently blocking rows). Added explicit `REVOKE INSERT, UPDATE, DELETE, TRUNCATE ... FROM authenticated, anon, PUBLIC` → UPDATE/DELETE now hard-error (insufficient_privilege).

**Tested (local runtime):** amendment + event created via helper; **UPDATE/DELETE on amendment_events denied (insufficient_privilege)**; cross-tenant RLS = 0/0/0 on all three tables; exec-team insert denied for non-admin, allowed for head.

## Story

As a developer,
I want the amendments tables with an append-only event trail,
so that modification requests are auditable like the lead Timeline.

## Acceptance Criteria

1. **Given** migration `0065_amendments.sql` **When** applied **Then** `public.amendments(id, tenant_id, unit_id, lead_id, description, status, logged_by, created_at, updated_at)` exists with `amendment_status` enum `(requested, acknowledged, in_progress, done, rejected)` and `ENABLE`/`FORCE` RLS.
2. **And** `public.amendment_events` is append-only (INSERT only; no UPDATE/DELETE for app roles).
3. **And** a `tenant_execution_team(tenant_id, user_id)` membership table exists, head-managed.
4. **And** cross-tenant RLS smoke tests pass for all three tables.

## Tasks / Subtasks

- [ ] **Task 1 — Migration `0065`**: `CREATE TYPE amendment_status`; `CREATE TABLE amendments` (FKs unit_id→units, lead_id→leads ON DELETE RESTRICT, logged_by→users) + RLS+FORCE; `CREATE TABLE amendment_events` (append-only — REVOKE UPDATE/DELETE from authenticated, INSERT via SECURITY DEFINER helper only, mirror `lead_timeline` `0012`/`0015`); `CREATE TABLE tenant_execution_team(tenant_id, user_id, PRIMARY KEY)` + RLS.
- [ ] **Task 2 — Apply + RLS smoke** for all three tables.

## Dev Notes

- Mirror the immutable `lead_timeline` pattern (no UPDATE/DELETE grant; INSERT via definer helper). [Source: 0012/0015 lead_timeline]
- Execution team = membership table, NOT a role tier. Head manages membership. [Source: architecture-builder-ops-v2.md §13.1]
- Migration `0065` per arch; confirm head.

## References
- [Source: epics.md#Story 16.1; architecture-builder-ops-v2.md §6, §13.1]
