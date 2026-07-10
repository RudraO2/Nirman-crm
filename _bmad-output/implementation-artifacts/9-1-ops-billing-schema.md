# Story 9.1 — Ops/billing schema (plans, payments, platform_admins, audit, tenant billing columns)

**Status:** ready-for-dev · **Epic:** 9 (Platform Ops Console) · **Design:** `9-ops-console-design.md`
**Depends on:** nothing functionally, but land AFTER 8.3's migration `0087` — use the next free number (**`0088`**). Confirm with `supabase migration list` first.
**Migration:** one new file `0088_ops_billing_schema.sql`, applied via `supabase db push --linked`. NEVER MCP apply.

---

## Goal

Add the data layer for the ops console + subscription/entitlement, reusing the existing `tenants.status` chokepoint (0056). Schema only — functions/cron (9.2), UI (9.3+) come later. Access to these tables is **platform-admin/service-role only**; tenant users must never read another builder's billing/audit.

## Acceptance Criteria

- **AC-1** — `plans` table: `id uuid pk`, `name text not null`, `monthly_price_placeholder numeric` (nullable — prices deferred), `quota_minutes int`, `quota_messages int`, `is_active bool not null default true`, `created_at`. Seed 2-3 placeholder rows (e.g. Basic/Pro) with NULL/0 prices.
- **AC-2** — `tenants` gains: `paid_until timestamptz` (nullable), `plan_id uuid references plans(id)`, `grace_days int not null default 3`. Back-fill existing active tenant(s): `plan_id` = a default plan, `paid_until` = NULL (they're the pre-existing prod tenant, treated active).
- **AC-3** — `tenant_payments` **append-only ledger**: `id`, `tenant_id references tenants(id)`, `amount numeric not null`, `method text not null check (method in ('upi','cash','bank','trust','other'))`, `period_start date`, `period_end date`, `recorded_by uuid` (platform admin), `note text`, `created_at timestamptz not null default now()`. No UPDATE/DELETE granted to anyone (corrections = reversing entries).
- **AC-4** — `platform_admins`: `user_id uuid pk references auth.users(id)`, `created_at`. This is the allowlist of who may use the ops console. **NOT tenant-scoped.** Seed with the founder's auth user id (document how — via `db query` post-deploy, not hardcoded in the migration).
- **AC-5** — `ops_audit_log` **immutable**: `id`, `actor uuid` (platform admin), `action text not null`, `target_tenant_id uuid`, `detail jsonb not null default '{}'`, `created_at timestamptz not null default now()`. No UPDATE/DELETE grant to anyone.
- **AC-6** — RLS: enable + FORCE on all four new tables. **No policies granting `authenticated` access** to `tenant_payments`, `platform_admins`, `ops_audit_log` (deny by default; only service-role/platform-admin fns in 9.2 touch them). `plans` may allow `authenticated` SELECT (needed later to show tier names), nothing else. Every FK column indexed.
- **AC-7** — The new `tenants` columns do NOT weaken the existing `auth_tenant_id()` gate or any RLS. Existing tenant queries unaffected (regression: existing app still reads its own leads).
- **AC-8** — Migration is idempotent-safe in the project's style (`IF NOT EXISTS`, enum guards), roll-forward only, header comment documenting purpose + the platform_admins seed step.

## Implementation notes

- Mirror existing conventions: `extensions.gen_random_uuid()` for PKs, `set_updated_at` trigger only where an `updated_at` exists (these are mostly append-only, so likely none), FK indexes, `COMMENT ON` each table citing Story 9.1.
- Do NOT add a `method`/`status` enum type unless it matches the codebase enum convention; a `CHECK` constraint is fine and simpler here (Rule of Three — one use, no new enum yet).
- `platform_admins` seed: after `db push`, run `supabase db query --linked "INSERT INTO public.platform_admins(user_id) VALUES ('<founder-auth-uid>')"`. Document the exact command in the story's completion notes.

## Test / verification

- `supabase db push --linked` applies cleanly on top of 0087; `supabase migration list` shows 0088.
- pgTAP or SQL checks: the 4 tables + 3 tenant columns exist; RLS enabled+forced; a plain `authenticated` role cannot SELECT `tenant_payments`/`ops_audit_log`/`platform_admins`; existing `get_my_leads` still returns the caller's leads (no regression).

## Out of scope (later stories)

- `renew_tenant` / `suspend_tenant` / `provision_tenant` / `expire_overdue_tenants` / `get_my_billing_status` fns + pg_cron → **9.2**.
- Ops app + auth/MFA, provisioning UI, billing UI, audit view → **9.3–9.5**.
- Tenant-side lockout screen → **9.6**.
- Quota enforcement (columns exist here; metering later).
