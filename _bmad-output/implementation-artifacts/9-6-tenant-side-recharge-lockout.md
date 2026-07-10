# Story 9.6: Tenant-side recharge / lockout screen

Status: ready-for-dev

<!-- Epics.md numbers this "9.3" (mobile recharge screen). Tracked as 9.6 to avoid the
     ops-console numbering collision, matching sprint-status.yaml / project-state.md. -->

## Story

As a **builder (tenant admin) whose prepaid subscription has lapsed** — and as an **employee of that tenant** —
I want the app to show a clear, friendly **"account paused → recharge"** state instead of silently breaking,
so that I understand *why* the workspace stopped working and *how* to restore it, without anyone being able to slip past the block.

## Context (business model — LOCKED)

Per-**project** monthly **prepaid** subscription, billed to the **builder**. Access is **pay-or-cut-off**.
Collection is **decoupled** from access: money is taken **out-of-band** (UPI / cash / bank) and the operator
records it in the ops console (`renew_tenant()` seam, Story 9.1/9.4). **No Razorpay / no in-app payment yet** —
this screen tells the user how to pay (contact the operator) and reflects status; it does NOT collect money.
When the operator records payment, `renew_tenant()` flips `status` back to `active` and access is restored on next
JWT refresh — no code change here. See memory `project_business_model`, [Source: epics.md#Epic-9], [Source: architecture.md "SaaS Activation Layer"].

## Acceptance Criteria

1. **(SECURITY — the whole point) The lockout is server-enforced, never a client-side overlay.**
   The recharge/paused UI is a **presentation of an already-enforced state**, not the enforcement itself.
   Access is cut at the DB by the `auth_tenant_id()` fail-closed chokepoint (migration 0056): for a `suspended`/`cancelled`
   tenant, every data RPC (`get_my_leads`, `get_lead_by_id`, mutations, etc.) already raises `42501` at Postgres.
   The dev MUST NOT introduce any path where lead/tenant data loads and is then hidden by a banner. Removing the
   UI via inspect-element / disabling Dart asserts / editing local state MUST leave the attacker with **no data**
   (all RPCs still denied server-side). **No new client-trusted gate.** Verify by: with a suspended tenant, confirm
   the data RPCs return `42501` independently of any UI. [Source: supabase/migrations/0056 chokepoint; 0088 note]

2. **Admin recharge screen (full).** When the signed-in user's JWT `app_metadata.role == 'admin'` and their tenant is
   not active, the app shows a dedicated recharge screen driven by `get_my_billing_status()` (0088) →
   `{status, plan_name, paid_until, days_remaining}`. It displays: current **plan name**, a human **status**
   (paused / expiring), and **days remaining** or **"overdue by N days"** when `paid_until < now()`. It explains
   **how to restore**: contact the operator to pay (out-of-band UPI/cash) — with a tap-to-contact affordance
   (phone/WhatsApp of the operator). It does **not** expose the payment ledger. [Source: 0088 get_my_billing_status]

3. **Employee paused screen (simple).** When `role != 'admin'`, the app does NOT call `get_my_billing_status()`
   (it is admin-only and returns `42501` for employees). Instead the employee sees a simpler state:
   "**Your workspace is paused. Please contact your admin.**" — no billing figures, no plan. The trigger is the
   tenant-gate RPC failure, not a billing read. [Source: 0088 fn is `role='admin'`-guarded]

4. **Detection & routing — mobile (Flutter, `apps/mobile`).** After login, when the home data load hits the
   tenant-gate failure (or, for admin, when `get_my_billing_status().status` ∈ {`suspended`,`cancelled`} or
   `paid_until < now()`), the router/app routes to a `/paused` screen and holds the user there — the 3-tab shell
   (`/home`, `/followups`, `/you`) and lead routes are not usable while paused. Login and password-change remain
   reachable (a paused user can still sign in / out). The check re-runs on app resume and on session refresh so
   that when the operator renews, the user is let back in without reinstalling. [Source: app_router.dart redirect]

5. **Detection & routing — admin web (`apps/admin`).** The `(app)` server layout (already `role==='admin'`-gated)
   additionally reads `get_my_billing_status()`; when not active it renders the recharge page (or redirects to a
   `/paused` route) instead of the app children. Because this is a server component, the gate runs on the server
   and cannot be removed client-side. [Source: apps/admin/src/app/(app)/layout.tsx]

6. **Visual language.** Warm **amber** (caution, not alarm-red; not the dark ops-cockpit style), calm and
   reassuring — this is a paying customer we want back, not an error. **Hindi-first** copy (primary Hindi, English
   secondary/supporting), consistent with the mobile app's audience. Matches the existing mobile theme system
   (`apps/mobile/lib/core/theme/app_theme.dart`) and admin Tailwind tokens — reuse tokens, don't hardcode a new palette.

7. **Graceful, no crashes / no loops.** A paused state must never crash the app or cause a redirect loop. Transient
   network errors (not a `42501` gate failure) must NOT be misread as "paused" — distinguish the tenant-gate/billing
   signal from a generic network error and show a normal retry for the latter. Active tenants see zero change.

8. **No new migration.** `get_my_billing_status()` already exists on prod (head `0091`). This story is **app-layer only**
   (Flutter + Next). Verify the fn signature/return before wiring; do not add DB objects. [Source: 0088 deployed]

## Tasks / Subtasks

- [ ] **Task 1 — Confirm the server-side enforcement is already airtight (AC #1, #8).**
  - [ ] Re-read `auth_tenant_id()` (0056) + `get_my_billing_status()` (0088) to confirm: suspended → data RPCs `42501`; billing fn readable by admin even when suspended; employee billing → `42501`.
  - [ ] On the local Docker stack, set a test tenant `status='suspended'` and prove `get_my_leads` returns `42501` with NO rows — document this as the enforcement proof. (Do NOT test against prod.)
- [ ] **Task 2 — Mobile: billing/paused state provider (AC #2,#3,#4,#7).**
  - [ ] Add a Riverpod provider that, on home load / resume / session refresh, determines paused-ness: for `role=='admin'` call `get_my_billing_status()`; for employees, treat the tenant-gate RPC `42501` as paused. Cache; distinguish `42501` (paused/denied) from network errors (retry).
  - [ ] Run `dart run build_runner build --delete-conflicting-outputs` after adding `@riverpod`.
- [ ] **Task 3 — Mobile: `/paused` recharge screen + router wiring (AC #2,#3,#4,#6).**
  - [ ] New `features/billing/ui/paused_screen.dart` (warm amber, Hindi-first). Admin variant: plan, days remaining / overdue-by-N, contact-operator (tap phone/WhatsApp). Employee variant: "workspace paused, contact admin."
  - [ ] Extend `app_router.dart` redirect to route paused users to `/paused` and keep them there (login/password-change still reachable); re-evaluate on resume + auth refresh.
- [ ] **Task 4 — Admin web: paused page + server-layout gate (AC #2,#5,#6).**
  - [ ] In `apps/admin/src/app/(app)/layout.tsx` (server), read `get_my_billing_status()`; when not active render the recharge page / redirect to `/paused`. Reuse the server supabase client (`@/lib/supabase/server`).
  - [ ] New paused/recharge page component (amber, Hindi-first, contact-operator affordance). **Read `node_modules/next/dist/docs/` before writing** — this Next.js has breaking changes (see apps/admin/AGENTS.md).
- [ ] **Task 5 — Operator contact config (AC #2,#3).**
  - [ ] Decide where the operator's contact (phone/WhatsApp) comes from — a build-time const / env is fine for now (out-of-band collection). Do NOT hardcode a personal number in source without Rudra's value; use a config constant with a documented placeholder.
- [ ] **Task 6 — Tests + verification (AC #1,#7).**
  - [ ] Mobile: unit-test the paused-state provider (admin suspended → paused; admin active → not; employee `42501` → paused; network error → retry-not-paused). Keep `flutter analyze` at 0, full suite green.
  - [ ] Admin: verify the server gate renders paused for a suspended tenant and passes through for active. `tsc` + `next build` clean.
  - [ ] End-to-end proof of AC#1: suspended tenant → remove the UI banner (devtools) → confirm no data is reachable.

## Dev Notes

### Threat model (why this is a real lockout)
- **Enforcement lives in Postgres, not the client.** The chokepoint `auth_tenant_id()` (0056) filters on `tenants.status`;
  a suspended tenant resolves to a NULL tenant, so every `SECURITY DEFINER` data RPC fail-closes with `42501`. The
  recharge screen is cosmetic on top of that. An attacker deleting the DOM/overlay, patching the compiled Flutter app,
  or replaying an old JWT still gets **zero rows** — the JWT's `tenant_id` claim only *names* the tenant; the DB
  re-checks `status` on every call. **Do not add a client-only gate that would create a bypass by removing it.**
- Corollary: never fetch data "eagerly then hide it." The paused screen should *replace* the data flow, and even if it
  didn't, the data flow returns nothing. Both belt and suspenders, but the DB is the belt.

### Files to touch
- **Mobile UPDATE** `apps/mobile/lib/router/app_router.dart` — the `redirect` at line 45 is the single auth gate
  (session + `must_change_password`). Add paused routing here; preserve the cold-start `INITIAL_SESSION` handling,
  the alarm-ring exemption (line 54), and the must-change-password flow. Do not break existing redirects.
- **Mobile NEW** `apps/mobile/lib/features/billing/ui/paused_screen.dart` + a provider under `features/billing/providers/`.
- **Mobile READ** `apps/mobile/lib/core/theme/app_theme.dart` for amber tokens; `features/auth/data/auth_repository.dart`
  for how sessions/JWT role are read (`app_metadata`).
- **Admin UPDATE** `apps/admin/src/app/(app)/layout.tsx` — server gate (line 14 role check) is where the billing check goes.
- **Admin NEW** a `/paused` route/page under `apps/admin/src/app/(app)/` (or a sibling group) + component.
- **Admin READ** `apps/admin/src/lib/supabase/server.ts`, `apps/admin/src/proxy.ts` for the auth pattern.

### Data contract
- `get_my_billing_status()` → `jsonb {status, plan_name, paid_until, days_remaining}`. **Admin-only** (`role='admin'` else `42501`).
  Deliberately bypasses `auth_tenant_id()` so a suspended admin can still read it. `days_remaining` is `ceil((paid_until-now)/1d)`
  and is **negative when overdue** — render "overdue by N days" for `< 0`. `paid_until` may be NULL (never paid / pure trial). [Source: 0088:205]
- Status values seen: `active`, `trial`, `suspended`, `cancelled` (+ grace, if present). Treat anything other than `active`/`trial`
  (with `paid_until` in the future) as "show recharge." Confirm the exact enum against `tenants.status` before coding.

### Constraints / conventions
- **No freestyle UI**: follow the mobile theme + admin Tailwind tokens; if the visual direction needs design work, involve `bmad-ux` rather than inventing a palette. Amber + Hindi-first is the brief.
- **Local-only testing** (free): use the Docker Supabase stack; NEVER flip a real prod tenant's status to test. `apps/admin` `next dev` currently points at **PROD** (see nirman-crm/CLAUDE.md footgun) — do not run admin actions against prod while testing suspension.
- Flutter: `flutter analyze` 0 errors, suite green; run `build_runner` after `@riverpod`. Next: read the vendored docs first; `tsc` + `next build` clean.

### Project Structure Notes
- New mobile feature folder `features/billing/` is consistent with the existing `features/<domain>/{ui,providers,data}` layout.
- Admin `/paused` under the `(app)` group keeps it behind the existing auth boundary; ensure the paused route itself is not gated *out* by its own billing check (avoid a redirect loop — AC #7).

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Epic-9 (Story 9.1 ACs; 9.3 recharge deferral)]
- [Source: supabase/migrations/0088_prepaid_billing.sql#get_my_billing_status (line 205)]
- [Source: supabase/migrations/0056 — tenant-status chokepoint `auth_tenant_id()`]
- [Source: apps/mobile/lib/router/app_router.dart#redirect (line 45)]
- [Source: apps/admin/src/app/(app)/layout.tsx (role gate, line 14)]
- [Source: memory project_business_model — per-project prepaid, decoupled collection]
- [Source: nirman-crm/CLAUDE.md — migrations file-based; admin dev points at prod footgun]

## Dev Agent Record

### Agent Model Used

(to be filled by dev-story)

### Debug Log References

### Completion Notes List

### File List
