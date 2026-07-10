---
baseline_commit: 6afb52c29cedad6b9657bec60aaf59a66310332e
---

# Story 9.2: Platform-admin ops backend — audited, guarded operations seam

Status: done  <!-- Ralph-loop: written -> coded -> 3-lens review -> fixed. 32/32 pgTAP + 0 regressions (prepaid 20/20, builder-ops 15/15) on local Docker 2026-07-10. NOT yet committed to git / pushed to prod — see Completion Notes (deploy 0088 then 0089). -->>

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the platform operator (founder),
I want a cross-tenant set of platform-admin-guarded, audit-logged operations — record a payment / renew, suspend, reactivate, and read every tenant's billing state, ledger, and audit trail —
so that the ops console (UI in 9.3) has one hardened, fail-closed backend seam to drive `renew_tenant()` and browse the ledger, without ever handing a service-role key to a client and without any tenant being able to reach another tenant's data.

## Context & Design Lock (read first)

Story 9.1 shipped the **billing seam** (migration `0088`): `plans`, `tenant_payments`, `renew_tenant()` (service-role only), `expire_lapsed_tenants()` (hourly cron), `get_my_billing_status()` (tenant-admin read). 9.1 built **no UI and no cross-tenant surface**.

This story (9.2) builds the **cross-tenant ops backend** — the single surface that crosses ALL tenants. Per `epics.md` § Epic 9 it is the "super-admin/creator ops console (service-role, audit-logged, separate surface) to drive `renew_tenant()` + browse the ledger." Per Winston's design (`9-ops-console-design.md` §3, §5): a **separate deployment** whose privileged actions "go through server-side handlers / edge fns that (a) re-verify the caller is a platform admin, (b) write an `ops_audit_log` row."

**Scope of THIS story = the DB layer only** (mirrors how 9.1 shipped): the platform-admin identity, the immutable audit ledger, and the guarded + audited RPCs. The console UI, the separate Vercel deployment, MFA/TOTP, and the app-side lockout screen are **deferred to 9.3** (`9-ops-console-design.md` splits these into scaffold/provisioning/billing-UI/lockout stories). **Do NOT build any `apps/*` page, edge function, or auth flow in 9.2.**

**Architecture decision (locked for this story): RLS-native, no service-role in a client.** The design doc floated either (a) an app holding the service-role key server-side that re-verifies platform-admin in Node, or (b) authenticated platform-admin JWTs calling guarded SECURITY DEFINER RPCs. We take **(b)** — it matches the whole project's fail-closed SECURITY-DEFINER convention (0054/0056/0088) and Story 8.3's "every privileged surface authenticates its caller in-fn" rule: the guard and the audit write live **in the database**, where a client cannot bypass them, and there is **no service-role key to leak**. The ops app (9.3) signs in a platform-admin user via Supabase auth and calls these RPCs with that JWT. The future Razorpay webhook keeps calling the raw `renew_tenant()` seam (already service-role-granted) directly — zero rework.

- Source of truth: `_bmad-output/planning-artifacts/epics.md` § Epic 9 (9.2 line), `nirman-crm/_bmad-output/implementation-artifacts/9-ops-console-design.md`.
- **Migration number is `0089`.** Prod head `0086`; `0087` reserved by Story 8.3 (in-review); `0088` = Story 9.1. Run `supabase migration list` before adding the file. Never MCP `apply_migration`.

## Acceptance Criteria

1. **Platform-admin identity (`public.platform_admins`).** Migration `0089_ops_console_backend.sql` creates `platform_admins (user_id uuid PRIMARY KEY, note text, created_at timestamptz NOT NULL DEFAULT now())`. It is a **cross-tenant** allowlist (NOT tenant-scoped, no `tenant_id`). `user_id` holds the `auth.users` id of a founder/operator; following the `tenant_payments.recorded_by` convention it is a plain `uuid` (no FK to `auth.users`) so the slice is testable on the local stack without provisioning GoTrue rows. The table has `ENABLE`+`FORCE ROW LEVEL SECURITY`, **no** policy for `anon`/`authenticated` (deny-all), and `REVOKE ALL` from `PUBLIC, anon, authenticated` — reachable only via SECURITY DEFINER fns. The migration seeds **no** rows (the operator inserts their own `user_id` post-deploy; documented).

2. **Immutable audit ledger (`public.ops_audit_log`).** Creates `ops_audit_log (id uuid pk default extensions.gen_random_uuid(), actor_user_id uuid, action text NOT NULL, target_tenant_id uuid, detail jsonb, created_at timestamptz NOT NULL DEFAULT now())`. Append-only: `ENABLE`+`FORCE RLS`, deny-all (no policies), `REVOKE ALL` from `PUBLIC, anon, authenticated` — no client may `SELECT/INSERT/UPDATE/DELETE` it directly; the only writer is the SECURITY DEFINER ops fns (INSERT only), the only reader is `ops_list_audit()`. Index `ops_audit_log (created_at DESC)` for the newest-first browse. `target_tenant_id` is a plain `uuid` (nullable — some actions are not tenant-scoped), no FK, so an audit row survives even if a tenant is later hard-deleted (audit must be permanent).

3. **`is_platform_admin()` helper.** `RETURNS boolean`, `STABLE`, SECURITY DEFINER, `SET search_path = public, extensions`. Returns `EXISTS (SELECT 1 FROM public.platform_admins WHERE user_id = auth.uid())`. Every ops fn calls it as its first line; a caller for whom it returns false is rejected with `RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501'`. `auth.uid()` NULL (no JWT / service-role with no sub) ⇒ false ⇒ denied — fail-closed.

4. **`ops_renew_tenant(p_tenant_id uuid, p_plan_id uuid, p_amount_inr integer, p_method text, p_note text default null)`.** SECURITY DEFINER, platform-admin-guarded. It (a) guards via `is_platform_admin()`, (b) delegates to the 9.1 seam `public.renew_tenant(...)` — reusing all its transaction/stacking/reactivation logic, **not re-implementing it**, (c) writes one `ops_audit_log` row `{action:'renew_tenant', target_tenant_id:p_tenant_id, actor_user_id:auth.uid(), detail:{plan_id, amount_inr, method, note, result}}`, and (d) returns the seam's `jsonb {tenant_id, status, paid_until, payment_id}`. Because it delegates, `tenant_payments.recorded_by` is stamped with the platform admin's `auth.uid()` (correct — that operator recorded the payment).

5. **`ops_suspend_tenant(p_tenant_id uuid, p_reason text default null)` and `ops_reactivate_tenant(p_tenant_id uuid, p_note text default null)`.** SECURITY DEFINER, guarded. Each locks the tenant (`SELECT ... FOR UPDATE`), raises `tenant_not_found` (`P0002`) if absent, flips `tenants.status` (`→ 'suspended'` / `→ 'active'` respectively), and writes an `ops_audit_log` row (`action` = `'suspend_tenant'` / `'reactivate_tenant'`, `detail` carries the reason/note and the previous status). Each returns `jsonb {tenant_id, status}`. Suspend is idempotent-safe (already-suspended → stays suspended, still audit-logged is acceptable; a no-op flip must not error). Reactivate does **not** touch `paid_until` (a manual reactivation may precede payment; `renew_tenant` is the paid path). Neither modifies `auth_tenant_id()` — the status flip alone drives cutoff/restore through the existing 0056 chokepoint.

6. **Cross-tenant reads for the console.** Three guarded SECURITY DEFINER read fns, each denying a non-platform-admin (`42501`):
   - `ops_list_tenants()` → `TABLE(tenant_id uuid, name text, status public.tenant_status, plan_name text, paid_until timestamptz, days_remaining int)` — **all** tenants (this is the cross-tenant morning-triage list), `days_remaining` = `ceil((paid_until-now())/86400)` or NULL, ordered by `paid_until NULLS LAST`.
   - `ops_list_tenant_payments(p_tenant_id uuid)` → `SETOF public.tenant_payments` for one tenant, newest `paid_at` first (the per-tenant ledger).
   - `ops_list_audit(p_limit integer default 100, p_offset integer default 0)` → `SETOF public.ops_audit_log`, newest `created_at` first (global immutable audit browse); `p_limit` clamped to a sane max (e.g. ≤ 500).

7. **Fail-closed authority + grants.** All `ops_*` fns and `is_platform_admin()` `REVOKE ALL FROM PUBLIC, anon`; the `ops_*` fns `GRANT EXECUTE TO authenticated` (the guard does the real authority check — a non-platform-admin authenticated caller is still denied `42501`). They are **not** granted to `anon`. `platform_admins` and `ops_audit_log` are deny-all RLS with no policies. A caller who is not in `platform_admins` can call nothing privileged; a platform admin from no particular tenant can read/act across all tenants (that is the whole point of the surface). The raw `renew_tenant()`/`expire_lapsed_tenants()` grants from 9.1 are **unchanged**.

8. **Free / local-testable.** The whole slice runs on the free local Docker Supabase stack, no payment provider, no GoTrue rows required. pgTAP covers: both tables FORCE-RLS + deny-all; all fns pin `search_path`; anon cannot execute; a non-platform-admin JWT is denied `42501` on every ops fn; a seeded platform-admin JWT can renew (delegates to `renew_tenant`, writes ledger **and** audit), suspend, reactivate; `ops_list_tenants` returns **multiple** tenants (cross-tenant proof); `ops_list_tenant_payments` returns the ledger row; `ops_list_audit` returns rows newest-first; audit rows cannot be updated/deleted by `authenticated` (immutability). Builder-ops + prepaid-billing invariant suites still pass (0 regressions).

## Tasks / Subtasks

- [ ] **Task 1 — Migration `0089_ops_console_backend.sql` tables** (AC: 1, 2, 7)
  - [ ] `BEGIN;` … `COMMIT;`, file-based, header comment in the 0088/0056 style; note "applied via `supabase db push --linked`; never MCP apply" and the "0087 reserved by 8.3" ordering caveat.
  - [ ] Create `public.platform_admins` (plain-uuid PK, no FK — mirror `tenant_payments.recorded_by`) + `COMMENT` explaining it is a cross-tenant allowlist.
  - [ ] Create `public.ops_audit_log` (append-only) + index `(created_at DESC)` + `COMMENT` (immutable, plain-uuid target, permanence rationale).
  - [ ] `ENABLE`+`FORCE ROW LEVEL SECURITY` on both, **no** policies (deny-all), `REVOKE ALL ... FROM PUBLIC, anon, authenticated`.
  - [ ] Seed **no** rows.
- [ ] **Task 2 — `is_platform_admin()` helper** (AC: 3, 7)
  - [ ] `RETURNS boolean STABLE SECURITY DEFINER SET search_path = public, extensions`; `EXISTS(... WHERE user_id = auth.uid())`.
  - [ ] `REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated;` (used only inside other definer fns, but grant is harmless and keeps it callable for a debug check) + `COMMENT`.
- [ ] **Task 3 — `ops_renew_tenant()`** (AC: 4, 7)
  - [ ] Guard `IF NOT is_platform_admin() THEN RAISE ... 42501`. Call `public.renew_tenant(p_tenant_id, p_plan_id, p_amount_inr, p_method, p_note)` into `v_result jsonb`.
  - [ ] INSERT `ops_audit_log` (`renew_tenant`, target, `auth.uid()`, detail jsonb incl. result). `RETURN v_result`.
  - [ ] Grants + `COMMENT` (note: delegates to the single 9.1 seam; future Razorpay webhook bypasses this and calls `renew_tenant` directly as service_role).
- [ ] **Task 4 — `ops_suspend_tenant()` + `ops_reactivate_tenant()`** (AC: 5, 7)
  - [ ] Guard; `SELECT status FROM public.tenants WHERE id = p_tenant_id FOR UPDATE`; `tenant_not_found` (P0002) if missing; capture `v_prev_status`.
  - [ ] `UPDATE ... SET status = 'suspended'|'active'`; INSERT audit row (prev status + reason/note in detail); `RETURN jsonb {tenant_id, status}`.
  - [ ] Grants + `COMMENT`. Reactivate must NOT touch `paid_until`.
- [ ] **Task 5 — Read fns `ops_list_tenants` / `ops_list_tenant_payments` / `ops_list_audit`** (AC: 6, 7)
  - [ ] Each guards first. `ops_list_tenants` LEFT JOIN plans, `days_remaining` ceil, `ORDER BY paid_until NULLS LAST`. `ops_list_tenant_payments` newest-first. `ops_list_audit` clamp `p_limit` to ≤ 500, `ORDER BY created_at DESC OFFSET p_offset LIMIT ...`.
  - [ ] Grants (`authenticated`) + `COMMENT` each.
- [ ] **Task 6 — Tests** (AC: 8)
  - [ ] pgTAP `supabase/tests/ops_console_backend.test.sql` in the `prepaid_billing.test.sql` style: fixtures (2 tenants + 1 plan + 1 platform-admin uuid), structural (FORCE-RLS, deny-all grants, search_path, anon-cannot-execute), authority (non-admin JWT → 42501 on every fn), behavioral (renew delegates + writes ledger + audit; suspend/reactivate flip + audit; list_tenants ≥ 2 rows; list_tenant_payments returns ledger; list_audit newest-first; audit immutable to authenticated).
  - [ ] Apply locally (`supabase migration up --local` or `db reset`) with 0089 on top of 0088; run pgTAP; re-run `builder_ops_invariants.test.sql` + `prepaid_billing.test.sql` — **0 regressions**.
- [x] **Task 7 — Sync BMAD docs** (housekeeping)
  - [x] This story + sprint-status update mirrored into `nirman-crm/_bmad-output/implementation-artifacts/`; epics.md 9.2 line unchanged (scope already recorded).

_(All tasks 1–7 completed; checkboxes reflect the Ralph-loop run.)_

### Review Findings (code review 2026-07-10 — 3-lens adversarial: Blind Hunter / Edge Case Hunter / Acceptance Auditor)

- [x] [Review][Fixed] **F1 (correctness):** `ops_list_audit` ordered by `created_at DESC` only; `created_at = now()` is transaction-start time → same-transaction (or same-microsecond) audit rows tie and browse non-deterministically. Caught by pgTAP test 29. **FIX:** added `seq bigint GENERATED ALWAYS AS IDENTITY` to `ops_audit_log` + index `(seq DESC)`; `ops_list_audit` now `ORDER BY seq DESC` (strictly monotonic, insertion-ordered). Locked by test 29.
- [x] [Review][Fixed-by-doc] **F2 (edge):** `ops_reactivate_tenant` on a genuinely lapsed tenant (`paid_until < now()`, non-null) is re-suspended by the hourly `expire_lapsed_tenants()` sweep — a goodwill reactivation silently reverts within the hour. **RESOLUTION:** reactivate is the "undo a manual/erroneous suspension" op (valid for future/NULL `paid_until`); to restore a *lapsed* tenant use `ops_renew_tenant` (extends `paid_until` AND flips active). Documented in the fn `COMMENT` + a `SCOPE CAVEAT` block; dedicated comp/grace op is future work. No code change to the flip (correct per AC5 "does not touch paid_until").
- [x] [Review][Fixed] **F3 (test-coverage):** AC1/AC2 "tables unreachable by direct client access" asserted for UPDATE/DELETE on `ops_audit_log` but not direct SELECT. **FIX:** added two assertions — `authenticated` cannot SELECT `ops_audit_log` nor `platform_admins` (admin allowlist never leaked). Plan 30 → 32.
- Dismissed as by-design (4): no FK on `platform_admins.user_id` / `ops_audit_log.target_tenant_id` (audit permanence + local testability, mirrors `tenant_payments.recorded_by`); suspend/reactivate flip from `cancelled` (platform-admin authority; the console UI gates which action is offered); no audit row on a *failed* renew validation (the platform-admin guard is the security boundary, not table CHECKs); suspend writes an audit row on a no-op re-suspend (harmless, keeps the trail complete).

## Dev Notes

### The non-obvious correctness traps
1. **The guard must be inside the delegate too, and `ops_renew_tenant` must NOT re-implement renew.** `renew_tenant()` is service-role-only and unguarded-by-JWT by design (9.1). `ops_renew_tenant` is the JWT-guarded doorway. If you re-implement the renew transaction here you duplicate the stacking/lock logic and the two will drift. Call the seam. A SECURITY DEFINER fn owned by the migration runner can execute `renew_tenant` regardless of its `service_role`-only GRANT (EXECUTE is checked against the definer/owner, who owns both).
2. **`auth.uid()` NULL must fail closed.** In `supabase test db` the fns run as superuser with no JWT unless you `set_config('request.jwt.claims', ...)`. `is_platform_admin()` returns false for NULL `auth.uid()` → every ops fn denies. Tests MUST set a `sub` claim matching a seeded `platform_admins.user_id` to exercise the happy path. This is also the real fail-closed guarantee.
3. **Audit permanence ⇒ no FK on `target_tenant_id`/`actor_user_id`.** An audit trail that a tenant delete could cascade away is not an audit trail. Plain uuids, mirroring `tenant_payments.recorded_by` (0088).
4. **Cross-tenant is the feature, not a leak.** Every other read in the codebase is tenant-scoped via `auth_tenant_id()`. These ops reads deliberately span all tenants — that is legitimate ONLY because `is_platform_admin()` gates them. Do not "fix" them to use `auth_tenant_id()`; that would return the platform admin's own (nonexistent) tenant and break the console.

### Regression guardrails (do NOT break these)
- **Do NOT modify `auth_tenant_id()` (0056), `renew_tenant()`/`expire_lapsed_tenants()`/`get_my_billing_status()` (0088), or any 9.1 grant.** 9.2 is purely additive.
- **Migration number is `0089`.** `supabase migration list` first; never MCP apply.
- **No `apps/*`, no `supabase/functions/*`.** UI + edge/MFA are 9.3.

### Source tree components to touch
- **NEW:** `nirman-crm/supabase/migrations/0089_ops_console_backend.sql` (the whole story).
- **NEW:** `nirman-crm/supabase/tests/ops_console_backend.test.sql`.
- **NOT touched:** any `apps/*`, any `supabase/functions/*`, `0056`, `0088`, `auth_tenant_id()`.

### Patterns to copy (byte-level conventions)
- **SECURITY DEFINER guard + grants + `SET search_path`:** `0088_prepaid_billing.sql` (`get_my_billing_status`) and `0054_harden_admin_role_guards.sql` (`assign_lead`).
- **FORCE-RLS deny-all table + `REVOKE ALL`:** `0088` (`plans`, `tenant_payments`).
- **`RETURNS TABLE` / `SETOF` read fn shape + `ORDER BY ... DESC`:** `get_my_leads` / builder-ops list RPCs.
- **pgTAP structure (plan/ok/is/throws_ok/`request.jwt.claims` set_config/finish/ROLLBACK):** `prepaid_billing.test.sql`.

### Testing standards summary
- pgTAP via `supabase test db`, or direct: `docker exec -i supabase_db_supabase psql -U postgres -d postgres -f - < supabase/tests/ops_console_backend.test.sql`.
- `auth.uid()` derives from `request.jwt.claims ->> 'sub'`; set it in tests to a seeded `platform_admins.user_id`.
- Keep migration idempotent-safe (`IF NOT EXISTS`, `CREATE OR REPLACE`).

### Project Structure Notes
- Migrations are strictly sequential integer-prefixed; next free number wins (`0089`).
- Keep both `_bmad-output/` copies (workspace root + repo) in sync (Task 7).

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Epic 9] (9.2 = ops console: service-role, audit-logged, drives renew_tenant + browse ledger)
- [Source: nirman-crm/_bmad-output/implementation-artifacts/9-ops-console-design.md] (§3 isolation, §4 data model platform_admins/ops_audit_log, §5 fns + platform-admin guard)
- [Source: nirman-crm/supabase/migrations/0088_prepaid_billing.sql] (renew_tenant seam, FORCE-RLS deny-all pattern, JWT guard)
- [Source: nirman-crm/supabase/migrations/0056_tenant_lifecycle_status.sql] (tenant_status enum, auth_tenant_id chokepoint)
- [Source: nirman-crm/supabase/migrations/0054_harden_admin_role_guards.sql] (SECURITY DEFINER role-guard idiom)
- [Source: nirman-crm/supabase/tests/prepaid_billing.test.sql] (pgTAP conventions)
- [Source: nirman-crm/CLAUDE.md] (migration rules, prod head 0086, never MCP apply)

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia / bmad-agent-dev, Ralph-loop run)

### Debug Log References

- Local Docker stack already at 0088 (9.1 seam verified present: `renew_tenant`, `get_my_billing_status`, `auth_tenant_id`). Applied 0089 directly into the container and ran pgTAP: `docker exec -i supabase_db_supabase psql -U postgres -d postgres -f - < supabase/tests/ops_console_backend.test.sql`.
- Iterating the migration during the loop: `DROP FUNCTION/TABLE IF EXISTS` the 0089 objects, then re-apply the file (objects are `CREATE [OR REPLACE] ... IF NOT EXISTS`, so a clean drop is needed to pick up the `seq` column add).
- Delegation verified: `ops_renew_tenant` (SECURITY DEFINER, owner postgres) successfully calls the `service_role`-only `renew_tenant` via implicit owner EXECUTE rights; `auth.uid()` inside the delegate resolves to the platform admin (test 18/19).

### Completion Notes List

- Implemented the DB layer only (no UI, no edge fn, no MFA) exactly per scope. `0089_ops_console_backend.sql` + pgTAP `ops_console_backend.test.sql`. UI/deployment/MFA/lockout = Story 9.3.
- **All 8 ACs verified on the free local stack. 32/32 pgTAP assertions pass, 0 failures.** Regression: prepaid_billing 20/20, builder_ops_invariants 15/15 — 0 regressions.
- Architecture: RLS-native — platform-admin JWT calls guarded SECURITY DEFINER RPCs; **no service-role key in any client**. Guard (`is_platform_admin()`) + audit write live in the DB, uncrossable by a client. The raw `renew_tenant()`/`expire_lapsed_tenants()` seam and grants from 9.1 are untouched; future Razorpay bypasses the ops fn and calls `renew_tenant` directly as `service_role`.
- Key traps enforced + tested: (1) `ops_*` all fail-closed on non-platform-admin (`42501`, tests 11–16); (2) `ops_renew_tenant` delegates to the 9.1 seam (no renew logic duplicated) and writes both a ledger row AND an audit row (tests 18–20); (3) cross-tenant reads legitimate only because gated (test 27 sees ≥2 tenants); (4) audit browse deterministic via monotonic `seq` (test 29); (5) both new tables deny-all FORCE-RLS, unreachable directly (tests 8–9 + the two added SELECT-denied assertions).
- 3-lens adversarial review (Blind Hunter / Edge Case Hunter / Acceptance Auditor): 3 findings (F1 ordering — fixed with `seq`; F2 reactivate/sweep interaction — fixed by documentation; F3 SELECT-denied coverage — fixed with 2 assertions), 4 dismissed by-design. See Review Findings above.
- **NOT yet done (prod):** git commit + `supabase db push --linked`. **Deploy ordering:** 0089 references `renew_tenant` from 0088, so 0088 (9.1) must land first (and 0087 from Story 8.3 precedes both by number). Run `supabase migration list` before pushing; never MCP apply. The operator must `INSERT INTO public.platform_admins (user_id) VALUES ('<their auth.uid()>')` post-deploy (the table is seeded empty by design).

### File List

- `nirman-crm/supabase/migrations/0089_ops_console_backend.sql` (NEW)
- `nirman-crm/supabase/tests/ops_console_backend.test.sql` (NEW)
- `_bmad-output/implementation-artifacts/9-2-ops-console-backend.md` (NEW — this story)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (MODIFIED — 9-2 line added)
- `nirman-crm/_bmad-output/implementation-artifacts/{9-2-...md, sprint-status.yaml}` (synced copies)

## Change Log

- 2026-07-10 — Story 9.2 drafted: platform-admin ops backend (migration 0089). DB-layer seam for the ops console; UI/MFA/deployment deferred to 9.3. Status → ready-for-dev.
- 2026-07-10 — Ralph-loop run (write → code → review → fix): 0089 (platform_admins, ops_audit_log, is_platform_admin(), ops_renew/suspend/reactivate + 3 cross-tenant reads) + pgTAP 32/32. 3-lens review → F1/F2/F3 fixed, 4 dismissed; 0 regressions. Status → done. Pending manual deploy (git commit + `db push`, 0088 before 0089).
