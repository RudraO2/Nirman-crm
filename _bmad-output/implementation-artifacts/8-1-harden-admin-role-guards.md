---
baseline_commit: 9d48ce2
---
# Story 8.1: Harden admin role guards against NULL-permissive bypass

Status: review

## Story

As a platform operator,
I want every admin-only database function to deny access when the JWT role claim is absent or NULL,
so that a momentarily role-less account (created mid-signup) can never execute an admin function once sign-up is public.

## Acceptance Criteria

1. **Given** the codebase-wide SECURITY DEFINER admin functions currently guard with NULL-permissive comparisons (`(... ->> 'role') <> 'admin'`, `v_actor_role <> 'admin'`, `v_actor_role NOT IN ('admin', …)`) — all of which evaluate to NULL (→ guard does not fire → access granted) when the role claim is absent **When** migration `0054_harden_admin_role_guards.sql` is applied **Then** every affected admin-only SECURITY DEFINER function is re-created so a NULL/absent role evaluates to **denied** (`IS DISTINCT FROM 'admin'` for scalar `<>`, `COALESCE(role,'') NOT IN (...)` for `NOT IN` guards).
2. **And** a test calling an admin function with a JWT that has no `app_metadata.role` returns a `permission_denied` (42501) error — not a successful execution.
3. **And** a test calling the same function with `role='admin'` still succeeds.
4. **And** table RLS policies (which already use the safe `= 'admin'` form, e.g. `whatsapp_templates`) are confirmed unaffected and left unchanged.
5. **And** the affected function list is enumerated in the migration comment for audit.
6. **And** functions already using the safe form (`IS DISTINCT FROM 'admin'`, or positive `= 'admin'` checks with an explicit `ELSE … deny`) are NOT modified (no behavioral churn).

## Tasks / Subtasks

- [x] **Task 1 — Enumerate affected functions from the live DB** (AC: 1, 5)
  - [x] Authoritative source for each `CREATE OR REPLACE` body is the *current* DB definition (`pg_get_functiondef`), since several functions were re-created by later review-patch migrations. Read-only introspection only — NEVER `apply_migration` (CLAUDE.md rule 2).
  - [x] Confirmed FIX list (17 fns): `<> 'admin'` deny-guards (15) — `assign_lead`, `bulk_assign_leads`, `get_builder_home_metrics`, `get_employee_active_lead_count`, `get_employee_active_lead_counts`, `get_employee_activity_stats`, `get_employee_performance_stats`, `get_funnel_stats`, `get_future_pool_match_count`, `get_lead_status_distribution`, `get_pipeline_activity_14d`, `list_assignable_leads`, `list_employees_for_assignment`, `reactivate_future_leads`, `search_leads_global`; `NOT IN` deny-guards (2) — `get_lead_name_for_notification` (`NOT IN ('admin','service_role')`), `list_employees_for_share` (`NOT IN ('employee','admin')`).
  - [x] Confirmed LEAVE list (already safe): `bulk_import_leads`, `check_phone_hashes`, `export_leads_data`, `get_export_count` (`IS DISTINCT FROM`); `revoke_share` (positive `= 'admin'`/`= 'employee'` with explicit `ELSE … RAISE 'permission_denied'` → NULL already denied).
- [x] **Task 2 — Write migration `0054_harden_admin_role_guards.sql`** (AC: 1, 5, 6)
  - [x] Header comment enumerating all 17 fixed functions + note that RLS policies and the 5 already-safe fns are intentionally untouched.
  - [x] For each fixed fn, `CREATE OR REPLACE FUNCTION` reproducing the **exact current body** verbatim, changing ONLY the guard:
    - scalar: `v_actor_role <> 'admin'` → `v_actor_role IS DISTINCT FROM 'admin'`; inline `(auth.jwt() -> 'app_metadata' ->> 'role') <> 'admin'` → `… IS DISTINCT FROM 'admin'`.
    - `NOT IN`: `v_actor_role NOT IN ('admin','service_role')` → `COALESCE(v_actor_role,'') NOT IN ('admin','service_role')`; `v_actor_role NOT IN ('employee','admin')` → `COALESCE(v_actor_role,'') NOT IN ('employee','admin')`.
  - [x] Preserve every existing `SET search_path`, `SECURITY DEFINER`, RETURNS signature, GRANT/REVOKE, and body logic byte-for-byte except the guard line. No signature drift (else `CREATE OR REPLACE` errors or leaves a duplicate overload).
- [x] **Task 3 — Apply via file-based migration** (AC: 1)
  - [x] `supabase migration list` first (0054 local-only), then `supabase db push --linked` → "Applying migration 0054_harden_admin_role_guards.sql... Finished supabase db push." NEVER MCP `apply_migration`.
- [x] **Task 4 — Verify NULL-denied / admin-allowed** (AC: 2, 3, 4)
  - [x] Re-introspected all 22 admin-mentioning SECURITY DEFINER fns: 0 retain `<> 'admin'`; 15 now `IS DISTINCT FROM 'admin'`; 2 NOT-IN guards `COALESCE`-wrapped; `revoke_share` + 4 already-safe untouched.
  - [x] Behavioral (`pg_temp.run_guard_tests()` with `set_config('request.jwt.claims',…)`): T1 role-less `<>`-fn → PASS denied; T2 admin → PASS executed; T3 role-less NOT-IN fn → PASS denied; T4 service_role → PASS (guard passed, regression intact).
  - [x] `pg_policies`: all 6 admin-referencing RLS policies use safe `= 'admin'`; 0 unsafe `<>`. Unchanged.
  - [x] Fidelity spot-check: `search_leads_global` / `list_assignable_leads` retained exact escape logic `replace(v_q,'\','\\')…` + `ESCAPE '\'`.

## Review Findings

_Code review 2026-05-29 (Blind Hunter + Edge Case Hunter + Acceptance Auditor). All 6 ACs verified satisfied; 17/17 fn bodies faithful to prior defs (guard-token-only change); service_role path + grants preserved._

- [x] [Review][Patch][RESOLVED] `share_lead` carried the identical NULL-permissive guard, uncovered by 0054 — latest def `supabase/migrations/0044_review_patches_4_4.sql:30` guarded `IF v_actor_role <> 'employee'` (SECURITY DEFINER, mutates `lead_shares` + timeline). Same 3VL bypass class 0054 fixes. **FIXED** in migration `0055_harden_share_lead_guard.sql` — guard now `v_actor_role IS DISTINCT FROM 'employee'`, body otherwise byte-for-byte from 0044, grants re-issued (`REVOKE … FROM PUBLIC, anon` / `GRANT … TO authenticated`). Applied via `db push --linked`. Verified live: guard_hardened=true, old_guard_present=false; behavioral `pg_temp.t_share_guard()` 3/3 PASS — T1 role-less denied (42501), T2 admin denied (employee-only intact), T3 employee passes guard (fails later at `tenant_missing`, role accepted).
- [x] [Review][Defer] "active lead" status filter formulated two opposite ways across `get_employee_active_lead_count` (NOT IN dead/sold/future), `get_employee_active_lead_counts` (IN hot/warm/cold), `get_employee_performance_stats` [0054 lines 347/377/494] — correct only while status enum stays exactly the 6 known values; deferred, pre-existing.
- [x] [Review][Defer] `permission_denied` raised without `ERRCODE='42501'` in 6 inline-jwt fns [0054 lines 243/395/471/594/701/733] — SQLSTATE-keying callers won't catch them; deferred, pre-existing (faithfully reproduced from prior defs).

## Dev Notes

### Root cause
SQL three-valued logic: when the role claim is absent, `(auth.jwt()->'app_metadata'->>'role')` is `NULL`. `NULL <> 'admin'` → `NULL`, and `IF NULL THEN RAISE …` does NOT fire → the deny-guard is skipped → caller proceeds. Same for `NULL NOT IN (…)` → `NULL`. Today every authenticated user has a stamped role, so this is latent; **Story 8.3 public sign-up creates a momentarily role-less `auth.users` row**, turning this into a live privilege/cross-tenant hole. Decision 35 couples this fix to 8.3 — **do it first** (security gate; 8.1 must be `done` before any other 8.x). [Source: architecture.md#Decision 35; epics.md#Story 8.1]

### Fix forms
- Scalar deny: `IS DISTINCT FROM 'admin'` — NULL-safe inequality (`NULL IS DISTINCT FROM 'admin'` → TRUE → guard fires → denied). Matches the pattern already shipped in `0052`/`0053`.
- `NOT IN` deny: wrap operand in `COALESCE(role,'')` so a NULL role becomes `''`, which is not in the allow-set → guard fires → denied. (`IS DISTINCT FROM` doesn't generalize to set membership.)

### Why the LEAVE list is safe
- `IS DISTINCT FROM` fns (`bulk_import_leads`, `check_phone_hashes`, `export_leads_data`, `get_export_count`) already NULL-deny.
- `revoke_share` uses positive branches `IF role='employee' … ELSIF role='admin' … ELSE RAISE permission_denied`. A NULL role matches neither branch → hits `ELSE` → denied. Already correct; touching it adds churn risk.

### Scope discipline
Migration is **pure DDL `CREATE OR REPLACE`** — no schema/data change, no mobile, no admin web. Idempotent-ish: re-running re-applies identical bodies. The single risk is body drift during transcription → mitigated by sourcing each body from `pg_get_functiondef` and changing only the guard token.

### Project Structure Notes
- Migration file: `supabase/migrations/0054_harden_admin_role_guards.sql` (next sequential number; `0053` is the current head). [Source: architecture.md#New Migrations]
- Keep `_bmad-output/` (canonical) and `nirman-crm/_bmad-output/` story copies in sync. [Source: CLAUDE.md]
- Mobile not touched → no `flutter analyze` needed for this story.

### References
- [Source: epics.md#Story 8.1: Harden admin role guards against NULL-permissive bypass]
- [Source: architecture.md#SaaS Activation Layer (V2) — Decision 35; New Migrations `0054`]
- [Source: nirman-crm/CLAUDE.md — file-based migrations via `supabase db push --linked`; never MCP `apply_migration`]
- [Source: supabase/migrations/0052_bulk_import.sql, 0053_export_log_and_rpcs.sql — existing `IS DISTINCT FROM 'admin'` pattern to mirror]

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia)

### Debug Log References

- Live introspection (read-only `execute_sql`, no `apply_migration`): enumerated all SECURITY DEFINER fns + guard styles; pulled exact current bodies for the 17 to re-create.
- `supabase db push --linked` → applied `0054`; `supabase migration list` confirmed 0054 local→remote synced.
- Post-apply re-introspection + `pg_temp.run_guard_tests()` behavioral suite (4/4 PASS) + `pg_policies` RLS scan (6/6 safe).

### Completion Notes List

- 17 admin-only SECURITY DEFINER functions hardened against NULL/absent JWT role: 15 scalar guards `<> 'admin'` → `IS DISTINCT FROM 'admin'`; 2 set-membership guards wrapped operand in `COALESCE(role,'')`.
- 5 functions intentionally left unchanged (already NULL-safe): `bulk_import_leads`, `check_phone_hashes`, `export_leads_data`, `get_export_count` (`IS DISTINCT FROM`), `revoke_share` (positive branches + ELSE-deny). RLS policies untouched (all positive `= 'admin'`).
- Bodies reproduced verbatim from live `pg_get_functiondef`; only the guard token changed. No signature drift; escape/regex logic in search fns preserved.
- Behavioral verification (live): role-less JWT denied (both guard styles); `role='admin'` allowed; `service_role` regression for `get_lead_name_for_notification` preserved.
- Code review (self, 3-layer adversarial): no blocking findings; no auto-fixes required. `BEGIN/COMMIT` wrapper explicit (Supabase also wraps migrations) — harmless.
- No mobile/web touched → `flutter analyze` N/A. Pure DDL migration.

### Change Log

- 2026-05-29: Implemented Story 8.1 — migration `0054_harden_admin_role_guards.sql` re-creating 17 admin-only SECURITY DEFINER functions with NULL-safe role guards (F-1 / Decision 35). Applied + verified on linked remote (project `vhgruadourflpxuzuxfn`).
- 2026-05-29: Code review (3-layer) — Edge Case Hunter found `share_lead` (employee-only) carried the same NULL-permissive guard, uncovered by 0054. Patched in migration `0055_harden_share_lead_guard.sql` (`IS DISTINCT FROM 'employee'`). Applied + verified live (3/3 guard tests PASS). Two pre-existing nits (status-filter formulation, missing ERRCODE on 6 inline-jwt fns) logged to `deferred-work.md`.

### File List

**New**
- `nirman-crm/supabase/migrations/0054_harden_admin_role_guards.sql`
- `nirman-crm/supabase/migrations/0055_harden_share_lead_guard.sql` (code-review follow-up)
