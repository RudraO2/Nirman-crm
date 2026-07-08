---
baseline_commit: 9d48ce2
context:
  - _bmad-output/planning-artifacts/epics.md#Story 8.2
  - _bmad-output/planning-artifacts/architecture.md#SaaS Activation Layer (V2)
---
# Story 8.2: Tenant lifecycle status and 14-day trial

Status: done

## Story

As a platform operator,
I want each tenant to carry a lifecycle status and trial window,
so that access can be gated on active/trial state and later tied to billing.

## Acceptance Criteria

1. **Given** the `tenants` table has no lifecycle fields **When** migration `0056_tenant_lifecycle_status.sql` is applied **Then** `tenants` gains a `status` field constrained to exactly `trial | active | suspended | cancelled` and a `trial_ends_at timestamptz` (nullable).
2. **And** new tenants default to `status = 'trial'` with `trial_ends_at = now() + interval '14 days'` (column defaults, so an `INSERT` that names neither column produces a 14-day trial).
3. **And** the existing V1 tenant (the single pre-existing row) is back-filled to `status = 'active'` with `trial_ends_at = NULL` — its users must experience **zero** change in access.
4. **And** app-layer and RLS access checks treat only `status IN ('trial','active')` as permitting login/data access; users of a `suspended` or `cancelled` tenant are denied **at the data layer** (RLS returns zero rows / SECURITY DEFINER RPCs fail-closed), not merely hidden in the UI.
5. **And** the gate is enforced through a single chokepoint so it covers every existing tenant-scoped table and every SECURITY DEFINER function without per-policy edits, and it is **fail-closed** (unknown/missing tenant or NULL status → denied).
6. **And** the change does not introduce RLS recursion on `public.tenants` and does not regress any existing verified behavior (mobile login + all Epic 1–7 RPCs still work for the active V1 tenant).

## Tasks / Subtasks

- [x] **Task 1 — Migration `0056_tenant_lifecycle_status.sql` (schema + defaults + back-fill)** (AC: 1, 2, 3)
  - [x] Confirmed next number via `supabase migration list` — `0055` head → this is `0056`. File-based, never MCP apply.
  - [x] Created enum `public.tenant_status AS ENUM ('trial','active','suspended','cancelled')` guarded by `DO $$ IF NOT EXISTS (… pg_type …) $$`.
  - [x] `ADD COLUMN status public.tenant_status NOT NULL DEFAULT 'trial'` + `ADD COLUMN trial_ends_at timestamptz DEFAULT (now() + interval '14 days')` (nullable). Verified: udt=tenant_status NOT NULL default 'trial'; trial_ends_at nullable default now()+14d.
  - [x] Back-fill `UPDATE public.tenants SET status='active', trial_ends_at=NULL;` after add-column. Verified: V1 "Nirman Media" → active / NULL.
  - [x] `COMMENT ON COLUMN` on both, referencing Story 8.2 / Decision 37.
- [x] **Task 2 — Fail-closed status gate via the `auth_tenant_id()` chokepoint** (AC: 4, 5, 6)
  - [x] Redefined `public.auth_tenant_id()` to return JWT tenant uuid only when `status IN ('trial','active')`, else NULL — single chokepoint, no per-policy edits.
  - [x] Preserved UUID regex format guard verbatim (malformed claim → NULL; verified T6).
  - [x] `SECURITY DEFINER` so internal `public.tenants` read bypasses RLS → no recursion (verified: tenants SELECT under authenticated returns row, no stack-depth error). Kept `STABLE` + `SET search_path = ''`, fully-qualified.
  - [x] Grants preserved: `REVOKE … FROM PUBLIC; GRANT … TO authenticated, service_role;`.
  - [x] Single PK lookup `WHERE t.id = <jwt_uuid> AND t.status IN ('trial','active')`.
  - [x] Parameterless + STABLE (planner evaluates once/query; tenants 1-row PK lookup).
- [x] **Task 3 — Apply via file-based migration** (AC: 1)
  - [x] `supabase migration list` (0056 local-only) → `supabase db push --linked` → "Applying migration 0056_tenant_lifecycle_status.sql... Finished supabase db push."
- [x] **Task 4 — Verify (live, read-only `execute_sql` + behavioral)** (AC: 1–6)
  - [x] Schema verified (see Task 1). V1 = active / trial_ends_at NULL.
  - [x] Defaults probe (insert naming only `name`, rolled-back/deleted): status='trial', trial_ends_at ~14d → PASS (T7).
  - [x] Gate behavioral `pg_temp.t_gate()` 8/8 PASS: active V1 → id; suspended/cancelled/malformed → NULL; trial → id; reactivated → id. End-to-end RLS (V1 flipped suspended in rolled-back tx): active=4 users/1 tenant visible, suspended=0 rows everywhere.
  - [x] No-recursion: `SELECT … FROM public.tenants` as authenticated returns row, no stack-depth error.
  - [x] Regression: `get_lead_status_distribution()` under active V1 JWT → 6 rows (auth_tenant_id resolves). V1 confirmed still `active`, tenant_count=1 (throwaway probes cleaned).
- [x] **Task 5 — Sync canonical + repo copies** (CLAUDE.md)
  - [x] `_bmad-output/` + `nirman-crm/_bmad-output/` story copies synced. Migration in `nirman-crm/supabase/migrations/0056_…`.

## Review Findings

_Code review 2026-05-29 (Blind Hunter + Edge Case Hunter + Acceptance Auditor). Auditor: all 6 ACs satisfied; deviation guards clean (no billing columns, no trial auto-expiry, no freestyle UI). No blocking/patchable findings._

- [x] [Review][Dismiss] **No-recursion relies on owner BYPASSRLS** (flagged High×2, static reviewers couldn't verify) — VERIFIED live: `auth_tenant_id` owner=`postgres`, `rolbypassrls=true`; `tenants` is FORCE RLS so the role attribute (not ownership) breaks the `tenants_self_visible → auth_tenant_id → tenants` cycle. Matches existing SECURITY DEFINER fns (`assign_lead`/`export_leads_data`/`share_lead` all postgres-owned). End-to-end RLS test confirmed no stack-depth error. Codebase-wide established pattern, not a novel risk.
- [x] [Review][Dismiss] **Back-fill `UPDATE` has no `WHERE`** (flagged Major×3, "unsafe if replayed on populated multi-tenant DB") — correct-by-construction: file-based migrations run exactly once per DB (tracked in `supabase_migrations`); at apply time the only rows are the pre-existing V1 tenant(s) (public signup is 8.3+), so blanket promote→active is the intended back-fill. Already applied; V1 correctly active. Editing an applied migration is disallowed; nothing is broken.
- [x] [Review][Dismiss] **Enum-exists check not schema-scoped** (minor) — `pg_type WHERE typname='tenant_status'` without namespace; applied cleanly (type created in `public`), migration runs once. No impact.
- [x] [Review][Defer] **`auth_tenant_id()` now reads `tenants` on every RLS evaluation** (perf) — inherent to a data-layer status gate; `STABLE` + single PK lookup on a 1-row-per-tenant table (hot in cache). Lowest-cost option vs caching status in the JWT (which would force re-issuing JWTs on status change). Logged to `deferred-work.md` for future-scale revisit.
- [x] [Review][Defer] **8.3 ordering hazard** — when `signup-create-tenant` lands, do NOT call `auth_tenant_id()` in the same transaction before the new `tenants` row is committed, and create the tenant with `status='trial'` (allowed) so the gate resolves. Not a 0056 defect; logged for the 8.3 author.

## Dev Notes

### Architectural approach — single chokepoint (the key decision)
Every tenant-scoped RLS policy in this codebase compares `tenant_id = public.auth_tenant_id()` (see `0003_cr_patch_jwt_only_rls.sql`), and every SECURITY DEFINER RPC derives tenant via `public.auth_tenant_id()`. That makes `auth_tenant_id()` the **one** place to enforce the lifecycle gate. Returning NULL for a non-active tenant cascades to "zero rows everywhere" — `tenant_id = NULL` is NULL→false in every USING clause. This satisfies AC4/AC5 (data-layer denial, all tables, no per-policy churn) and matches the doc: "App + RLS gate access on `status IN ('trial','active')`" [Source: architecture.md#Decision 37].

### Why SECURITY DEFINER (recursion trap)
`tenants_self_visible` RLS policy (`0003:40`) is `USING (id = public.auth_tenant_id())`. If `auth_tenant_id()` SELECTs `public.tenants` under caller RLS, evaluating that policy calls `auth_tenant_id()` which reads `tenants` which evaluates the policy… → infinite recursion / stack depth error. Fix: `SECURITY DEFINER` (function owner is `postgres`, which has BYPASSRLS) → the internal read skips RLS entirely → no recursion. This is the standard Postgres pattern for "RLS policy needs to read the same/related table." Keep `STABLE` + `SET search_path = ''` and fully-qualify every object.

Current `auth_tenant_id()` (`0003:18-30`) is `LANGUAGE sql STABLE SET search_path=''`, JWT-only, no table read. The redefinition adds the tenants lookup and flips to SECURITY DEFINER. **Preserve the UUID regex format guard verbatim** — it is load-bearing fail-closed behavior (malformed claim → NULL).

### Trial-end behavior — OPEN product decision, non-blocking
Exact trial-end behavior (soft lock vs read-only) is an open product decision [architecture.md#Decisions explicitly NOT taken]. Per the epic AC: implement the **status gate only**; default unconfigured trial-end to a **soft lock** (i.e. a tenant whose `trial_ends_at` has passed is NOT auto-suspended by this story — there is no cron/trigger flipping `trial`→`suspended` here). `trial` remains an allowed status, so an expired-but-still-`trial` tenant keeps access until a future story (8.x/9.1 billing) or an operator flips `status`. Do NOT build auto-expiry in 8.2. [Source: epics.md#Story 8.2 Open question]

### Billing seam (D8) — columns NOT in this story
Decision D8 says build the billing seam (`stripe_customer_id`, `subscription_id`, `plan`, `seats`) but those land in migration `0058` in the later billing epic (9.1), not here. 8.2 adds only `status` + `trial_ends_at`. Do not pre-add billing columns. [Source: architecture.md#D8, New Migrations table]

### Enum vs CHECK
Use a Postgres enum `public.tenant_status` for convention-consistency with `user_role`/`lead_status`/`timeline_event_type` and because the doc says "enum" [architecture.md#Decision 37]. AC1's "constrained to exactly these 4" is satisfied by the enum domain.

### App-layer gate (AC4 "app-layer … login")
The data-layer (RLS) gate is the hard requirement and is fully delivered by Task 2. A friendlier app-layer signal (mobile/web showing "workspace suspended" instead of an empty screen) is desirable but: (a) mobile login uses `setSession` then queries data → a suspended tenant yields empty data = soft lock, satisfying AC4's denial requirement; (b) the admin web public/auth surfaces that would show a tailored message are built in 8.3+. **Do not freestyle a mobile UI change here.** If a minimal app-layer check is added, it must be a read of `tenants.status` gated through approved patterns; otherwise rely on the RLS gate and note the UX message as follow-up. Flag to Rudra if a visible "suspended" message is wanted in mobile now (would need Flutter work + a status-exposing RPC).

### Previous story intelligence (8.1)
- File-based migrations only; `supabase db push --linked`; `supabase migration list` first. NEVER MCP `apply_migration` (desyncs history). [CLAUDE.md]
- Verify live with read-only `execute_sql` + `pg_temp.<fn>()` behavioral suites using `set_config('request.jwt.claims', …)` — pattern proven in 8.1 (0054/0055 guard tests). Roll back any data mutations in tests.
- `auth_tenant_id()` is referenced by the 17 admin SECURITY DEFINER fns hardened in 0054 — changing it touches that whole surface; the regression spot-check (Task 4) guards it.
- Keep both `_bmad-output/` copies in sync.

### Project Structure Notes
- Migration: `nirman-crm/supabase/migrations/0056_tenant_lifecycle_status.sql` (next sequential; `0055` is head). [architecture.md#New Migrations]
- No mobile (`apps/mobile`) or admin-web (`apps/admin`) code in this story → no `flutter analyze` needed (DB-only). If an app-layer message is later added, that becomes its own task.
- Pure additive DDL + one redefinition + one back-fill UPDATE. No data loss. Idempotency: `CREATE TYPE`/`ADD COLUMN` run once via the migration runner.

### References
- [Source: epics.md#Story 8.2: Tenant lifecycle status and 14-day trial]
- [Source: architecture.md#SaaS Activation Layer (V2) — Decision 37; D8; New Migrations `0056`; Security Invariants #4]
- [Source: supabase/migrations/0001_init_tenants_users.sql — tenants table + RLS]
- [Source: supabase/migrations/0003_cr_patch_jwt_only_rls.sql — `auth_tenant_id()` definition + JWT-only RLS chokepoint]
- [Source: nirman-crm/CLAUDE.md — file-based migrations via `supabase db push --linked`; never MCP `apply_migration`; do not regress verified infra]

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia)

### Debug Log References

- `supabase migration list` → 0055 head; `supabase db push --linked` applied `0056_tenant_lifecycle_status.sql` ("Finished supabase db push.").
- Live verification via read-only MCP `execute_sql`: schema introspection, `pg_temp.t_gate()` behavioral suite (8/8 PASS), end-to-end RLS proof (V1 flipped suspended inside `BEGIN…ROLLBACK`, auto-restored), regression spot-check.

### Completion Notes List

- Added `tenants.status` (`public.tenant_status` enum: trial|active|suspended|cancelled, NOT NULL default 'trial') and `tenants.trial_ends_at` (timestamptz nullable, default now()+14d). New tenants get a 14-day trial by column default; existing V1 tenant back-filled to active/NULL (zero access change — verified 4 users + 1 tenant still visible).
- Enforced the lifecycle gate at a SINGLE chokepoint: redefined `public.auth_tenant_id()` to return the JWT tenant uuid only when its status IN ('trial','active'), else NULL. Cascades to all tenant-scoped RLS policies + all SECURITY DEFINER RPCs (they compare `tenant_id = auth_tenant_id()`), with no per-policy edits. Fail-closed: malformed claim, missing tenant, suspended, cancelled → NULL → zero rows.
- Made the function SECURITY DEFINER to read `public.tenants` without recursing through the `tenants_self_visible` RLS policy (which itself calls auth_tenant_id). Preserved STABLE, `SET search_path=''`, the UUID format-guard regex, and grants.
- Behavioral proof: suspended tenant → auth_tenant_id NULL → 0 users & 0 tenants visible at the data layer (AC4). Active → normal access, tenants SELECT works (no recursion, AC6). Regression: get_lead_status_distribution() → 6 rows for active V1 (auth_tenant_id resolves correctly through the 0054-hardened admin fns).
- Trial-end behavior (soft lock vs read-only) left as the open product decision: NO auto-suspend/cron in 8.2 — `trial` stays an allowed status until an operator/billing flips it. Billing seam columns (D8) deferred to 0058.
- DB-only story: no mobile/admin-web code touched → `flutter analyze` N/A. App-layer "suspended" UX message noted as follow-up (would need Flutter + a status RPC) — flagged in Dev Notes.

### File List

**New**
- `nirman-crm/supabase/migrations/0056_tenant_lifecycle_status.sql`

## Change Log

- 2026-05-29: Implemented Story 8.2 — migration `0056_tenant_lifecycle_status.sql`: `tenants.status` enum + `trial_ends_at`, 14-day trial defaults, V1 back-fill to active, and fail-closed lifecycle gate via redefined SECURITY DEFINER `auth_tenant_id()` (single chokepoint, no RLS recursion). Applied + verified live (8/8 gate tests, end-to-end RLS, regression clean).
