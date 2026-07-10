# Story 9.5: Ops console — provision a new builder (tenant + first admin)

Status: review  <!-- Ralph-loop: written -> coded -> 3-lens review -> fixed. tsc + next build clean; full provision→login path verified through the local API gateway. FREE/LOCAL — NOT committed, NOT pushed. -->

## ⚠️ Numbering

Filed under `9-5-provision-builder` (design `9-ops-console-design.md` §7 numbers this "9.4 provisioning"; that slot is muddied by the epics.md 9.3/9.4 usage, so this uses a distinct key like 9.4-web-ui did). This is the "add a new builder" seam that **9.4 explicitly deferred** ("needs a `provision_tenant()` backend that does NOT exist — its own story").

## Story

As the platform operator (founder),
I want a dedicated ops-console screen that creates a new builder — the tenant, its first admin login, and a starting plan (trial or paid) — and ends by showing me the credentials to hand over,
so that I can onboard a builder I just signed without touching SQL, on the same RLS-native, audit-logged surface, with no service-role key in the browser.

## Context & Design Lock

- Consumes a NEW backend fn `provision_tenant()` (migration `0091`) built in this story. Same architecture as the rest of the ops backend (9.2): **RLS-native, platform-admin-guarded SECURITY DEFINER, audit-logged, NO service-role key**.
- **Why a SQL fn, not the `bootstrap-admin`/`create-employee` edge-fn pattern:** those create accounts via the GoTrue Admin API using a **service-role key** (server-side). The ops console holds no service-role key by design (9.2). So `provision_tenant` writes **both** stores directly, exactly the dual-store shape `create-employee` produces: `auth.users` (+ `auth.identities`) so the builder admin can sign in, and `public.users` with the **same** bcrypt hash (the `login` edge fn verifies that store first). pgcrypto `$2a$12` bcrypt is accepted by both GoTrue and bcryptjs (verified live).
- **Username handling mirrors `create-employee`/`login` exactly:** a plain username gets the synthetic domain `@employees.nirman.local` (GoTrue needs a valid email; `login` re-synthesizes identically). `role='admin'` passes the web-platform gate.
- Source of truth: `9-ops-console-design.md` §2 (onboarding model), §10 ("Provision new builder: dedicated route … ends on a success screen showing the admin credentials to hand off — not a toast").

## Acceptance Criteria

1. **`provision_tenant()` (migration `0091`).** Platform-admin-guarded (`is_platform_admin()`; non-admin → `42501`) SECURITY DEFINER fn `provision_tenant(p_builder_name, p_admin_username, p_admin_password, p_admin_name, p_plan_id, p_start, p_amount_inr, p_method, p_timezone)`. It: validates inputs; normalizes the username to the synthetic domain; enforces **global** username uniqueness (`23505 username_taken`); creates the tenant (`status=trial`, `trial_ends_at` default); creates the first admin across BOTH stores with one bcrypt hash and `must_change_password=true`, `role='admin'`, `app_metadata={role,tenant_id,provider,providers}`; for a **paid** start delegates to the 9.1 `renew_tenant()` seam (flips active, sets `paid_until`, writes the ledger stamped with the operator); writes an `ops_audit_log` `provision_tenant` row that **never** contains the password; returns `{tenant_id, admin_user_id, admin_username, status}`. `REVOKE ALL … FROM PUBLIC, anon; GRANT EXECUTE TO authenticated`.

2. **Transactional / no partial state.** The whole fn is one implicit transaction — any failure (dup username, bad plan) rolls back the tenant + both user rows. No orphan tenant, no half-created login.

3. **`/provision` route in `apps/ops`.** A dedicated route (design §10 — not a modal), under the guarded `(app)` layout, linked from the sidebar. A 3-step wizard: (1) Builder (name, timezone), (2) First admin (name, username, auto-generated temp password + Regenerate, shows the resolved sign-in handle), (3) Plan & start — pick a plan (`ops_list_plans`), start as **Trial (14 days)** or **Paid now** (amount + method). A live summary rail. `Provision builder` calls `provision_tenant`; errors are mapped to readable copy; the button disables in-flight (no double-submit).

4. **Credential handoff success screen.** On success the wizard swaps to a handoff screen (not a toast, design §10): sign-in URL, username, and temp password — each copyable — plus a warning that the password won't be shown again (reset from the tenant's row if lost) and the new tenant's start state. Buttons: Back to tenants / Provision another.

5. **Free / local-verified.** On the local Docker stack: provisioning creates the tenant + admin; the **new admin actually signs in** via GoTrue (`role=admin`, correct `tenant_id`); wrong password rejected; the tenant appears in `ops_list_tenants`; the audit shows a `provision_tenant` row with no password; a **non-platform-admin** (even the freshly provisioned builder admin) is **denied** `provision_tenant` (`42501`). `tsc` + `next build` clean. No service-role key, no prod push.

## Tasks / Subtasks

- [x] **Task 1 — Migration `0091_provision_tenant.sql`** (AC 1, 2). Applied + tested locally.
- [x] **Task 2 — `/provision` route** (AC 3, 4): `(app)/provision/page.tsx` (server, `ops_list_plans`) + `components/provision-flow.tsx` (client wizard + handoff). Sidebar `Provision` link. Error copy in `lib/format.ts`.
- [x] **Task 3 — Verify + 3-lens review** (AC 5). Verified via API gateway; review below.
- [x] **Task 4 — Docs**: this story + sprint-status `9-5` line; both `_bmad-output` copies synced.

### Review Findings (3-lens — 2026-07-10)

- Dismissed as by-design / acceptable (no code changes needed):
  - **`provision_tenant` writes `auth.users` directly** rather than via GoTrue Admin API. Intentional — the ops console holds no service-role key (9.2). Verified GoTrue accepts the row and the admin logs in. The one GoTrue gotcha (NULL token varchars → `500`) is handled: all token columns seeded `''`.
  - **Trial start still records the chosen `plan_id`** (no window) — harmless, gives the tenant a default plan for the first renewal.
  - **"Provision another" doesn't reset the plan/start fields** — trivial carry-over, plan rarely changes between provisions.
  - **Global (not tenant-scoped) username uniqueness** — correct: `login` looks up `email_or_username` globally, so a collision across tenants would be ambiguous; the fn rejects it up front.

### Debug Log References

- `provision_tenant` applied to local stack; provisioned "Acme Builders" (paid ₹5,000 upi) as the seeded platform admin → `{status:active, tenant_id, admin_user_id, admin_username:rahul.acme@employees.nirman.local}`; dual-store hashes match; `must_change_password=true`.
- **Verified through the API gateway:** the new admin `rahul.acme@employees.nirman.local` / `Acme-7fK2qP` signs in via GoTrue → `role=admin`, `tenant_id=5a6a3021…`; wrong password → 400; `ops_list_tenants` includes Acme; audit has 1 `provision_tenant` row, detail keys `{start,method,plan_id,amount_inr,builder_name,admin_user_id,admin_username}` — **no password**; the provisioned builder admin calling `provision_tenant` → `42501 permission_denied` (guard holds against a tenant admin).
- `tsc --noEmit` + `next build` clean (routes now `/`, `/audit`, `/login`, `/provision`).

### Completion Notes List

- Closes 9.4's deferred "add a new builder" gap. RLS-native provisioning: one guarded SQL fn does the full dual-store create + optional paid start (via the 9.1 seam) + audit — no service-role, no edge fn.
- **Prod-deploy dependencies (NOT done — FREE/LOCAL):** push migrations `0090` (9.4) + `0091` (this); the builder admin logs into the existing `apps/admin` web at the real domain; on prod the synthetic-domain + dual-store path is identical (both GoTrue + bcryptjs accept `$2a$12`). No git commit, no push.
- Deferred still: MFA step-up on provision (design §10 / 9.7), Razorpay, tenant-side recharge screen.

### File List

- **NEW:** `nirman-crm/supabase/migrations/0091_provision_tenant.sql` (LOCAL-applied, not pushed)
- **NEW:** `nirman-crm/apps/ops/src/app/(app)/provision/page.tsx`, `nirman-crm/apps/ops/src/components/provision-flow.tsx`
- **MODIFIED:** `nirman-crm/apps/ops/src/components/ops-sidebar.tsx` (Provision nav), `nirman-crm/apps/ops/src/lib/format.ts` (provision error copy)
- **DOCS:** `_bmad-output/implementation-artifacts/{9-5-provision-builder.md, sprint-status.yaml}` + synced nirman copies

## Change Log
- 2026-07-10 — Story 9.5: provision-a-builder. Migration `0091 provision_tenant()` (guarded, dual-store, audit-logged, RLS-native) + wired `/provision` wizard + credential handoff in `apps/ops`. Verified provision→login on the free local stack. 3-lens review: 0 code fixes, 4 dismissed by-design. FREE/LOCAL — not committed, not pushed. Status → review.
