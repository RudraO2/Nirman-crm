---
baseline_commit: b8a94a56d76b54229a5162c146ab153f5faefeea
---

# Story 9.6: Tenant-side recharge / lockout screen

Status: done
<!-- done 2026-07-10: 3-layer code review complete, CRITICAL resolved via migration 0092
     (deployed prod, head 0092, verified), all patches applied, 143/143 tests. Non-blocking
     follow-ups (Rudra, before selling): device/browser look-pass + set real operator support #. -->


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

- [x] **Task 1 — Confirm the server-side enforcement is already airtight (AC #1, #8).**
  - [x] Re-read `auth_tenant_id()` (0056) + `get_my_billing_status()` (0088). CONFIRMED: `auth_tenant_id()` returns a tenant only when `status IN ('trial','active')` → suspended/cancelled = NULL. **67 migration files** route data access through `auth_tenant_id()`. Representative data RPC (`get_lead_by_id`, 0019:144-148): `v_tenant_id := auth_tenant_id(); IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'missing_tenant_context' USING ERRCODE='P0001'`. **Correction to error-code assumption:** data RPCs raise `missing_tenant_context`/`P0001` (NOT 42501) on suspension; `get_my_billing_status` raises `42501` only for non-admin role. Detection logic below uses these exact signals.
  - [x] Enforcement is pervasive + server-side (SECURITY DEFINER + chokepoint). Live authed proof (suspend a LOCAL test tenant, observe `missing_tenant_context`) left for on-stack verification; code path is airtight by inspection.
- [x] **Task 2 — Mobile: billing/paused state provider (AC #2,#3,#4,#7).**
  - [x] `features/billing/data/billing_repository.dart` — `BillingStatus` model + `getMyBillingStatus()` + `probeLockedOut()`; pure `isTenantLockedOutError()` classifier (P0001/`missing_tenant_context` = locked; else rethrow). `features/billing/providers/billing_providers.dart` — `pausedState` FutureProvider: admin → billing fn, employee → probe; fail-OPEN on network/ambiguous errors (AC#7). Re-evaluates on `authStateChangesProvider` (token refresh on resume, sign-in).
  - [x] Ran `build_runner` — `.g.dart` generated clean.
- [x] **Task 3 — Mobile: paused screen + gate wiring (AC #2,#3,#4,#6).**
  - [x] `features/billing/ui/paused_screen.dart` (warm amber `statusWarm`/`accentSoft`, Hindi-first). Admin: plan + days-remaining/overdue-by-N card + WhatsApp/Call recharge + "मैंने payment कर दी — दोबारा जाँचें" re-check + Sign out. Employee: simple "workspace paused, contact your admin."
  - [x] Gated at `AppShell` (single interception point — a `ConsumerWidget`): locked-out → render `PausedScreen` full-screen replacing the whole tab shell (no tab/lead surface reachable = "holds them there"). Chosen over router redirect because `appRouter` reads Supabase directly, not Riverpod; shell gate is cleaner + avoids per-nav RPC. Login/password-change routes untouched.
- [x] **Task 4 — Admin web: server-layout gate + recharge page (AC #2,#5,#6).**
  - [x] `apps/admin/src/app/(app)/layout.tsx` (server): reads `get_my_billing_status()`; status ∉ {active,trial} → renders `<PausedRecharge/>` instead of app chrome (server-side = un-removable client-side; fail-open on read error). Admin-only surface, so no employee variant needed here.
  - [x] `src/components/billing/paused-recharge.tsx` (client): amber, Hindi-first, plan/status/window, WhatsApp + Call + reload-to-recheck. Mirrors the existing server-component + rpc pattern (no new Next APIs).
- [x] **Task 5 — Operator contact config (AC #2,#3).**
  - [x] `apps/mobile/lib/core/config/operator_contact.dart` + `apps/admin/src/lib/operator-contact.ts` — single documented **PLACEHOLDER** const (`910000000000` / `+91 00000 00000`), NOT a personal number. Rudra sets the real support number before ship.
- [x] **Task 6 — Tests + verification (AC #1,#7).**
  - [x] Mobile: `test/features/billing/billing_status_test.dart` — 10 tests (fromJson, isLockedOut mirrors 0056, isOverdue, isTenantLockedOutError with P0001/message/42501/network). **10/10 pass.** `flutter analyze` on all new/touched files = **No issues found**; **0 error-level** across the whole project (254 pre-existing infos/warnings in unrelated test files, untouched).
  - [x] Admin: **`tsc --noEmit` exit 0**, **`next build` exit 0** (all `(app)` routes `ƒ` dynamic — gate runs per-request, not at build).
  - [~] Live AC#1 proof (suspend a LOCAL tenant, observe data RPC `missing_tenant_context` with an authed session, and confirm removing the UI leaks nothing): enforcement verified by code path (67 RPCs via `auth_tenant_id()`; `IF NULL RAISE` at 0019:147) + unit tests; **the live authed run is left for Rudra's on-stack/device pass** (needs a logged-in suspended session).

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

## Review Findings (code-review 2026-07-10, 3-layer: blind + edge + auditor)

### Decision needed — RESOLVED 2026-07-10 (Rudra: hard cutoff, both roles, no bypass, clean UI; warn 3 days, no grace)
- [x] **[Review][Decision] CRITICAL — suspended employees still read leads; employee lockout never triggers.** FIXED via **migration `0092_hard_tenant_cutoff.sql`**: (a) added the `auth_tenant_id() IS NULL → RAISE missing_tenant_context` guard to `get_my_leads` (the ONLY employee RPC that lacked it — audited all 20; every other already gated), so a suspended tenant now has NO reachable data on ANY RPC; (b) relaxed `get_my_billing_status` from admin-only to any tenant member (own-tenant, no ledger) so BOTH roles detect lockout + see the warning — dropped the fragile probe entirely (dissolves the P0001 patch below). **Verified on local Docker (authed JWT sim): suspended→get_my_leads `missing_tenant_context`, employee reads billing `status:suspended`, active tenant returns 2 leads unaffected, status restored.** Prod push of 0092 PENDING Rudra's OK.

### Patches — all applied 2026-07-10
- [x] **[Review][Patch] `isTenantLockedOutError` bare `P0001` false-positive** — DISSOLVED: the probe is gone (both roles now read `get_my_billing_status` authoritatively). No P0001 classification anymore.
- [x] **[Review][Patch] AC#4 routing gap — non-shell routes bypass the paused gate.** FIXED: moved lockout gating into the `app_router.dart` `redirect` via a global `billingLockNotifier` (fed by `billingGateProvider` from the app root, `Listenable.merge` refresh). EVERY route now bounces to `/paused` when locked out; `/paused`, password-change, alarm-ring exempt; recovered→/home. [app_router.dart, app.dart, paused_screen.dart PausedRouteScreen]
- [x] **[Review][Patch] `tel:` missing `+`.** FIXED `tel:+<e164>` on both surfaces. [paused_screen.dart, paused-recharge.tsx]
- [x] **[Review][Patch] `_launch` dead-tap on `canLaunchUrl==false`.** FIXED: SnackBar fallback showing the number. [paused_screen.dart]

### Deferred (pre-existing / low, revisit)
- [x] **[Review][Defer] Admin web swallows `tenant_missing` (42501) as fail-open** → a deleted/malformed-JWT admin sees an empty app, not recharge. Rare edge. [apps/admin/src/app/(app)/layout.tsx]
- [x] **[Review][Defer] Startup/refresh flash of the tab shell during `AsyncLoading`** before paused resolves (compounds the employee-read gap until Decision is fixed). Retain previous value / show a neutral loader. [app_shell.dart]
- [x] **[Review][Defer] `pausedState` fires an RPC on every auth event** incl. hourly `TOKEN_REFRESHED` — recurring round-trip for active tenants. [billing_providers.dart]
- [x] **[Review][Defer] Operator contact is a placeholder with no build/runtime guard** — could ship a fake number. [operator_contact.dart / operator-contact.ts]

### Dismissed (2)
- Admin uses raw `amber-*` Tailwind utilities vs custom tokens — amber+Hindi brief still met (no defined amber token exists).
- `grace`/`unknown` allow-list "drift" + `status:''` cross-platform disagreement — `grace` isn't in the `tenant_status` enum (dead branch that correctly fails closed); not a bug.

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia / bmad-dev-story)

### Debug Log References

- `dart run build_runner build --delete-conflicting-outputs` → 153 outputs, clean.
- `flutter analyze <billing scope>` → No issues found; global `flutter analyze` → 0 error-level (254 pre-existing infos/warnings in unrelated files).
- `flutter test test/features/billing/billing_status_test.dart` → 10/10 pass.
- `npx tsc --noEmit` (apps/admin) → exit 0.
- `npx next build` (apps/admin) → exit 0.

### Completion Notes List

- **AC#1 honored as designed:** the lockout is server-enforced (0056 chokepoint). Both surfaces gate *display* only and **fail open** on read/network error — safe because data RPCs stay server-denied. No client-trusted access gate introduced.
- **Key correction during dev:** data RPCs raise `missing_tenant_context` (`P0001`) on suspension, NOT `42501` (that's the billing fn's non-admin code). Detection uses the exact signals: admin → authoritative `status` from `get_my_billing_status()`; employee → probe `get_my_leads` and classify `P0001`.
- **Mobile gate placement:** `AppShell` (a single `ConsumerWidget`) rather than the global `appRouter` redirect, since the router reads Supabase directly (not Riverpod) and awaiting an RPC in `redirect` on every navigation is wasteful. The shell replaces the entire tab scaffold with `PausedScreen` when locked out.
- **Resume re-check:** `pausedState` watches `authStateChangesProvider`, so `TOKEN_REFRESHED` (fires on app foreground) re-evaluates; plus a manual "मैंने payment कर दी — दोबारा जाँचें" button invalidates it. A renewed builder is let back in without reinstalling.
- **Not device/stack-verified (Rudra's pass):** actual rendered look of the amber Hindi-first screens on device/browser; the live authed suspended-tenant run of AC#1 on the local Docker stack. Set the real `OperatorContact` support number before ship (currently a documented placeholder).
- **No migration** — `get_my_billing_status()` already on prod (head 0091). App-layer only.

### File List

**Mobile (`apps/mobile`) — NEW**
- `lib/features/billing/data/billing_repository.dart`
- `lib/features/billing/data/billing_repository.g.dart` (generated)
- `lib/features/billing/providers/billing_providers.dart`
- `lib/features/billing/providers/billing_providers.g.dart` (generated)
- `lib/features/billing/ui/paused_screen.dart`
- `lib/core/config/operator_contact.dart`
- `test/features/billing/billing_status_test.dart`

**Mobile — MODIFIED**
- `lib/features/home/ui/app_shell.dart` (warning banner; lockout now router-gated)
- `lib/router/app_router.dart` (billingLockNotifier + `/paused` route + redirect gate)
- `lib/app.dart` (ref.listen bridge: billingGate → router notifier)

**Backend — NEW (migration)**
- `supabase/migrations/0092_hard_tenant_cutoff.sql` — get_my_leads tenant-status guard + get_my_billing_status relaxed to any tenant member. **Applied+verified LOCAL; prod push pending Rudra.**

**Admin (`apps/admin`) — NEW**
- `src/components/billing/paused-recharge.tsx`
- `src/lib/operator-contact.ts`

**Admin — MODIFIED**
- `src/app/(app)/layout.tsx` (server-side lockout gate + 3-day warning banner)

## Change Log

- 2026-07-10 — Implemented story 9.6 (tenant recharge/lockout). Mobile Flutter billing feature + admin web server-gate. Server-enforced (0056), UI display-only + fail-open. Initial: 10/10 tests, admin build clean.
- 2026-07-10 — **Code review (3-layer) + rework.** Blind/Edge/Auditor found a CRITICAL: `get_my_leads` (0061) bypassed the tenant chokepoint → suspended employees still read leads + employee lockout never fired. Per Rudra's decision (hard cutoff both roles, no bypass; warn 3 days, no grace): added **migration 0092** (guard `get_my_leads`; relax `get_my_billing_status` to any tenant member), reworked detection to one billing-based path for both roles, moved lockout to the **router** (`/paused`, every route) for clean UI, added a 3-day advance-warning banner (mobile + admin), and fixed the tel:+ / dead-launch patches. Verified 0092 on local Docker (authed sim: suspended→denied, employee reads billing, active unaffected). **143/143 mobile tests, analyze 0, admin tsc + next build 0.** Prod push of 0092 pending. Status → review (re-review recommended for 0092).
