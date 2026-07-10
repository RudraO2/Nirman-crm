---
baseline_commit: 6afb52c29cedad6b9657bec60aaf59a66310332e
---

# Story 9.1: Prepaid access-gating seam (schema + renew + auto-expiry)

Status: done  <!-- code-review clean 2026-07-10 (1 low patch fixed, 1 deploy note deferred). NOT yet committed to git / pushed to prod — see Completion Notes. -->>

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the platform operator,
I want each tenant's access tied to a prepaid `paid_until` date on a chosen plan, renewed through one internal `renew_tenant()` seam and auto-suspended on lapse,
so that I can collect payment out-of-band (UPI / cash / bank) and cut off — or restore — a builder's entire workspace at the DB layer, with **no** payment-provider integration yet and Razorpay bolting onto the same seam later with zero access rework.

## Context & Design Lock (read first)

This story **replaces** the abandoned "Stripe per-seat" design that was written into `epics.md` before the business model was locked. The market is commission-only; per-seat/per-sale fees fail. **Locked model (2026-07-09):** per-**project** monthly **prepaid** subscription ("recharge"), billed to the **builder**, **pay-or-cut-off**. Collection is **decoupled** from access — money taken out-of-band; access gated purely on the existing `tenants.status` fail-closed chokepoint.

- Source of truth: `_bmad-output/planning-artifacts/epics.md` § Epic 9 (rewritten), and `_bmad-output/brainstorming/brainstorming-session-2026-07-09-2247.md`.
- **Scope of THIS story = the DB seam only.** Deferred: 9.2 super-admin ops console (drives `renew_tenant`, browses ledger), 9.3 mobile "recharge" screen + Razorpay collection. **Do NOT build any UI, page, or edge function in 9.1.** No `apps/admin`, no `apps/mobile`, no `supabase/functions` changes.

## Acceptance Criteria

1. **Schema (migration `0088_prepaid_billing.sql`).** Creates `public.plans` (`id uuid pk`, `name text`, `price_inr integer`, `interval_months int default 1`, `is_active boolean default true`, `created_at`), `public.tenant_payments` ledger (`id uuid pk`, `tenant_id uuid` → tenants, `plan_id uuid` → plans, `amount_inr integer`, `method text`, `paid_at timestamptz default now()`, `covers_from timestamptz`, `covers_until timestamptz`, `recorded_by uuid null`, `note text null`, `created_at`), and adds `plan_id uuid` (FK → plans) + `paid_until timestamptz` to `public.tenants`. **No price amounts are hard-coded in application code** — they live in `plans` rows set by the operator.
2. **`renew_tenant(p_tenant_id uuid, p_plan_id uuid, p_amount_inr integer, p_method text, p_note text default null)` seam.** SECURITY DEFINER, `service_role`-only. In ONE transaction it: locks the tenant row; computes `covers_from = greatest(coalesce(paid_until, now()), now())` and `covers_until = covers_from + (plan.interval_months * interval '1 month')`; inserts a `tenant_payments` row; sets `tenants.paid_until = covers_until`, `tenants.plan_id = p_plan_id`, and flips `status` to `'active'` if it was not already `'active'`. Returns `jsonb {tenant_id, status, paid_until, payment_id}`.
3. **Stacking.** A second `renew_tenant` call made **before** the current `paid_until` extends from the existing `paid_until` (not from `now()`), so prepaid time never gets shortened by an early renewal. A renewal made **after** lapse extends from `now()`.
4. **Auto-expiry (`expire_lapsed_tenants()` + pg_cron hourly).** SECURITY DEFINER, `service_role`-only. Bounded, TOCTOU-safe sweep (FOR UPDATE SKIP LOCKED LIMIT 500, re-assert predicate inside UPDATE) that flips `status` `'active' → 'suspended'` for every tenant where `status = 'active' AND paid_until IS NOT NULL AND paid_until < now()`. Returns the count suspended. A `pg_cron` schedule `expire-lapsed-tenants` runs it hourly, **guarded** so the migration still applies where pg_cron is absent (local Docker). Lapse cuts off access purely through the existing `auth_tenant_id()` gate — **no new RLS surface, `auth_tenant_id()` itself is NOT modified.**
5. **NULL-`paid_until` tenants are never touched.** The live V1 prod tenant (backfilled `active`, `paid_until IS NULL`) and all trial tenants (`paid_until IS NULL`) are excluded from the sweep — expiry only ever suspends a tenant that has actually been given a prepaid window that has now passed.
6. **`get_my_billing_status()` read.** SECURITY DEFINER, `authenticated`, **admin-only**. Returns `jsonb {status, plan_name, paid_until, days_remaining}` for the caller's own tenant. It **must NOT use `auth_tenant_id()`** (that returns NULL for a suspended tenant, which is exactly when the recharge screen must render). Instead it derives the tenant id straight from the JWT claim with the same UUID-format guard used in `auth_tenant_id()`, and reads the tenant **regardless of status**. It never exposes the ledger or other tenants.
7. **Fail-closed authority.** `renew_tenant` and `expire_lapsed_tenants` are revoked from PUBLIC/anon/authenticated and granted only to `service_role`. `get_my_billing_status` denies a non-admin caller (`role IS DISTINCT FROM 'admin'`) and only ever returns the caller's own tenant (a caller from tenant A can never read tenant B). `plans` and `tenant_payments` have RLS enabled with **no** policy for `authenticated` (deny-all; reached only via the SECURITY DEFINER fns and `service_role`).
8. **Free / local-testable.** The entire slice runs on the free local Docker Supabase stack with no payment provider. pgTAP (or SQL) tests cover: renew extends, renew stacks from `paid_until`, expiry suspends a lapsed active tenant, expiry skips a NULL-`paid_until` tenant, `get_my_billing_status` returns while suspended, cross-tenant read denied, non-admin denied, and the `service_role`-only grants.

## Tasks / Subtasks

- [x] **Task 1 — Migration `0088_prepaid_billing.sql` schema** (AC: 1, 7)
  - [x] `BEGIN;` … `COMMIT;`, file-based, header comment in the sibling style (0056/0077); note "applied via `supabase db push --linked`; never MCP apply".
  - [x] Create `public.plans` and `public.tenant_payments` with the columns in AC1; FKs `ON DELETE RESTRICT` to match `users.tenant_id` convention.
  - [x] `ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS plan_id uuid REFERENCES public.plans(id)`, `ADD COLUMN IF NOT EXISTS paid_until timestamptz;` with `COMMENT ON COLUMN` explaining gating semantics (mirror 0056 comments).
  - [x] `ENABLE`+`FORCE ROW LEVEL SECURITY` on both new tables (matches builder-ops FORCE-RLS invariant); **no** `authenticated` policy (deny-all) + `REVOKE ALL`. Index on `tenant_payments(tenant_id, paid_at desc)` for ledger reads (9.2).
  - [x] Seed one placeholder `plans` row (`'Standard Monthly'`, `interval_months = 1`, `price_inr = 0`, `is_active`) guarded `WHERE NOT EXISTS` — operator-editable, amounts deferred.
- [x] **Task 2 — `renew_tenant()` seam** (AC: 2, 3, 7)
  - [x] `LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions`.
  - [x] `SELECT ... FROM public.tenants WHERE id = p_tenant_id FOR UPDATE`; raise `tenant_not_found`. `SELECT interval_months ... WHERE id = p_plan_id AND is_active`; raise `plan_not_found_or_inactive`.
  - [x] `covers_from = greatest(coalesce(paid_until, now()), now())`, `covers_until = covers_from + make_interval(months => interval_months)`; INSERT ledger (`recorded_by = auth.uid()`); UPDATE tenant `paid_until`, `plan_id`, `status='active'`.
  - [x] `RETURN jsonb_build_object('tenant_id','status','paid_until','payment_id')`.
  - [x] `REVOKE ALL ... FROM PUBLIC, anon, authenticated; GRANT EXECUTE ... TO service_role;` + `COMMENT`.
- [x] **Task 3 — `expire_lapsed_tenants()` + pg_cron** (AC: 4, 5, 7)
  - [x] Body modeled on `release_expired_holds()` (0077): bounded `LIMIT 500 FOR UPDATE SKIP LOCKED`, TOCTOU re-assert inside UPDATE, `IF NOT FOUND THEN CONTINUE`, returns count. Predicate `status='active' AND paid_until IS NOT NULL AND paid_until < now()`.
  - [x] `service_role`-only grants + `COMMENT`.
  - [x] Guarded pg_cron schedule via `pg_extension` DO-block: `cron.schedule('expire-lapsed-tenants','0 * * * *', ...)`.
- [x] **Task 4 — `get_my_billing_status()` read** (AC: 6, 7)
  - [x] SECURITY DEFINER, admin-only guard (`IS DISTINCT FROM 'admin'` → 42501).
  - [x] Tenant id via UUID-guarded JWT CASE (from 0056) **without** status filter → suspended tenant still readable. LEFT JOIN `plans` for `plan_name`.
  - [x] `days_remaining = ceil(extract(epoch from (paid_until-now()))/86400.0)::int` when non-null else null (negative when lapsed = valid signal).
  - [x] `REVOKE ... FROM PUBLIC, anon; GRANT EXECUTE ... TO authenticated, service_role;` + `COMMENT`.
- [x] **Task 5 — Tests** (AC: 8)
  - [x] pgTAP `supabase/tests/prepaid_billing.test.sql` (harness present) — 19 assertions covering all eight AC8 scenarios + structural grants/FORCE-RLS/search_path.
  - [x] Migration applies cleanly on local (`supabase migration up --local`, 0085/0086/0088) **without** pg_cron; sweep fn callable directly. **19/19 pass, 0 failures.** Builder-ops invariants regression: 0 failures.
- [x] **Task 6 — Sync BMAD docs** (housekeeping)
  - [x] epics.md Epic 9 rewrite + this story + sprint-status mirrored into `nirman-crm/_bmad-output/implementation-artifacts/` (repo has no `planning-artifacts` mirror dir; epics canonical at workspace root).

### Review Findings (code review 2026-07-10 — 3-lens adversarial, clean)

- [x] [Review][Patch] `get_my_billing_status` raised `tenant_missing` (42501) on a valid-format JWT tenant claim with no matching row, instead of returning a null-status object [nirman-crm/supabase/migrations/0088_prepaid_billing.sql] — FIXED + locked by test 20.
- [x] [Review][Defer] Migration 0088 applied before 0087 (reserved by Story 8.3); `supabase db push --linked` will apply 0087 out of numeric order when 8.3 lands. Deploy-coordination note (not a code defect) — deferred, tracked in deferred-work.md.
- Dismissed as noise/by-design (5): LIMIT-500/hr sweep cap (intentional, mirrors 0077); redundant `COALESCE` inside `GREATEST` (ignores NULL anyway); `p_method` enforced by table CHECK; cancelled→active reactivation (intended per locked pay-or-cutoff model); employee 42501 from billing read (no consumer until 9.3).

## Dev Notes

### The one non-obvious correctness trap
`get_my_billing_status()` is the ONLY tenant-scoped read in the codebase that must deliberately **bypass** `auth_tenant_id()`. Every other RPC uses `auth_tenant_id()` and is *supposed* to go dark when the tenant is suspended. This one is the exception: its whole job is to tell a **suspended** admin why they're locked out. If you scope it with `auth_tenant_id()` it will return nothing for exactly the tenants that need it, and the recharge screen (9.3) can never render. Parse the JWT tenant claim directly (UUID-guarded, no status filter). This is called out explicitly so it is not "fixed" into using `auth_tenant_id()` during review.

### Regression guardrails (do NOT break these)
- **Do NOT modify `public.auth_tenant_id()` (0056).** The suspend does the cutoff for free through the existing chokepoint. Touching it risks the whole tenant-isolation surface.
- **`expire_lapsed_tenants` MUST exclude `paid_until IS NULL`.** The live production tenant is `status='active'` with `paid_until IS NULL` (0056 backfill). A sweep that forgets this predicate would **suspend the live customer and every trial** on its first run. This is the highest-severity failure mode in the story.
- **Migration number is `0088`.** Prod head is `0086`; `0087` is reserved by Story 8.3 (harden-edge-function-auth, in-review). Run `supabase migration list` before adding the file. Never MCP `apply_migration`.
- Trials are governed by `trial_ends_at` (8.2), a separate and still-open product decision — **out of scope here.** Do not add trial-expiry logic to this sweep.

### Source tree components to touch
- **NEW:** `nirman-crm/supabase/migrations/0088_prepaid_billing.sql` (the whole story).
- **NEW:** test file under `nirman-crm/supabase/tests/` (or a committed SQL scenario).
- **NOT touched:** any `apps/*`, any `supabase/functions/*`, `0056_tenant_lifecycle_status.sql`, `auth_tenant_id()`.

### Patterns to copy (byte-level conventions)
- **pg_cron sweep shape + guarded schedule:** `0077_release_expired_holds.sql` — `FOR UPDATE SKIP LOCKED LIMIT 500`, re-assert-inside-UPDATE, `IF NOT FOUND THEN CONTINUE`, `RETURN v_count`, and the `pg_extension` guard around `cron.schedule`.
- **SECURITY DEFINER auth guard + grants:** `0054_harden_admin_role_guards.sql` (`assign_lead`) — `v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';`, `IS DISTINCT FROM 'admin'`, `ERRCODE='42501'`, `SET search_path TO 'public','extensions'`.
- **Fail-closed JWT tenant extraction (UUID guard):** `0056_tenant_lifecycle_status.sql` lines 61-68 — reuse the CASE, drop the `AND t.status IN (...)`.
- **Enum / `ADD COLUMN IF NOT EXISTS` / `COMMENT ON` idioms:** `0056`.

### Testing standards summary
- `supabase db push --linked` for prod; `supabase db reset` locally. CLI 2.101, linked (see `nirman-crm/CLAUDE.md`).
- pgcrypto/`gen_random_uuid` live in the `extensions` schema (0001) — reference as `extensions.gen_random_uuid()` if needed.
- Keep the migration idempotent-safe (`IF NOT EXISTS`, `CREATE OR REPLACE`) — siblings all are.

### Project Structure Notes
- Migrations are strictly sequential integer-prefixed files applied in order; the next free number wins. No conflict with the `epics.md` comment-numbering (which drifted from file-numbering during builder-ops) — file order is what `db push` uses.
- The repo (`nirman-crm/`) is the git root; the workspace also holds a synced `_bmad-output/` copy. Keep both epics/story copies in sync (Task 6).

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Epic 9: Billing — Per-Project Prepaid Subscription]
- [Source: _bmad-output/brainstorming/brainstorming-session-2026-07-09-2247.md] (locked monetization + access-control design)
- [Source: nirman-crm/supabase/migrations/0056_tenant_lifecycle_status.sql] (tenants.status, auth_tenant_id chokepoint, JWT UUID guard)
- [Source: nirman-crm/supabase/migrations/0077_release_expired_holds.sql] (pg_cron TOCTOU-safe sweep + guarded schedule)
- [Source: nirman-crm/supabase/migrations/0054_harden_admin_role_guards.sql] (SECURITY DEFINER role-guard + grants)
- [Source: nirman-crm/supabase/migrations/0001_init_tenants_users.sql] (tenants base columns, extensions schema)
- [Source: nirman-crm/CLAUDE.md] (migration rules, prod head 0086, never MCP apply, local-is-prod footgun)

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia / bmad-dev-story)

### Debug Log References

- Local Docker stack was mid-history (applied through 0084) with a stale `00075` shim entry in the migration history table → `migration up` refused. Repaired local-only: `supabase migration repair --status reverted 00075 --local`, then `supabase migration up --local` applied 0085/0086/0088 clean.
- pgTAP run directly in the db container: `docker exec -i supabase_db_supabase psql -U postgres -d postgres -f - < supabase/tests/prepaid_billing.test.sql`.

### Completion Notes List

- Implemented the DB seam only (no UI, no edge fn) exactly per scope. Migration `0088_prepaid_billing.sql` + pgTAP `prepaid_billing.test.sql`.
- **All 8 ACs verified behaviorally on the free local stack. 19/19 pgTAP assertions pass, 0 failures.** Builder-ops invariants re-run: 0 failures (no regression).
- Key traps enforced + tested: (1) `expire_lapsed_tenants` excludes `paid_until IS NULL` → the live V1 prod tenant + trials are never auto-suspended (AC5, test 17); (2) `get_my_billing_status` deliberately bypasses `auth_tenant_id()` so a suspended tenant's admin still reads status for the recharge screen (AC6, test 18); (3) renew stacks from `paid_until` not `now()` (AC3, test 14).
- `auth_tenant_id()` (0056) NOT modified — the suspend flip alone does the cutoff through the existing chokepoint.
- New tables use `ENABLE`+`FORCE` RLS with deny-all (no policies) matching the builder-ops FORCE-RLS invariant; SECURITY DEFINER fns (BYPASSRLS owner) + `service_role` still read/write.
- **NOT yet done (prod):** `supabase db push --linked` to apply 0088 to prod (0087 reserved by Story 8.3 must land first or be coordinated). pg_cron schedule only activates where the extension exists (prod), guarded so local apply succeeds without it.

### File List

- `nirman-crm/supabase/migrations/0088_prepaid_billing.sql` (NEW)
- `nirman-crm/supabase/tests/prepaid_billing.test.sql` (NEW)
- `_bmad-output/planning-artifacts/epics.md` (MODIFIED — Epic 9 rewritten to locked prepaid model)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (MODIFIED — 9.1 renamed + status)
- `_bmad-output/implementation-artifacts/9-1-prepaid-access-gating-seam.md` (NEW — this story)
- `nirman-crm/_bmad-output/implementation-artifacts/{9-1-...md, sprint-status.yaml}` (synced copies)

## Change Log

- 2026-07-10 — Story 9.1 implemented: prepaid access-gating seam (migration 0088 + pgTAP). Replaces abandoned Stripe per-seat design. 19/19 tests pass locally. Status → review.
- 2026-07-10 — Code review (3-lens adversarial): clean. 1 low patch fixed (`get_my_billing_status` missing-tenant → raise `tenant_missing`), regression-locked by test 20 (20/20 pass); 1 deploy-coordination note deferred; 5 dismissed. Status → done. Pending manual deploy: git commit + `supabase db push --linked` (coordinate 0088 with 8.3's 0087).
