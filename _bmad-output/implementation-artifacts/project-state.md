# Project State — what EXISTS (handoff snapshot)

_Last frozen: 2026-07-10. Purpose: a cold-start Amelia (or any agent) reads THIS first to know exactly what is already built, where it lives, and what's live vs local — then picks the next story. This lists what we HAVE. A short "next handles" list at the end names candidate stories to ask for — nothing there is built yet._

Repo: `nirman-crm/` (github.com/RudraO2/Nirman-crm, branch `main`). Supabase prod: `vhgruadourflpxuzuxfn`. Read `nirman-crm/CLAUDE.md` for the hard infra rules (migrations file-based via `db push --linked`, never MCP apply; prod-vs-local footguns).

---

## Surfaces we have (and where)

| Surface | Path | Stack | Status |
|---|---|---|---|
| **Mobile CRM** | `apps/mobile` | Flutter 3.44 / Dart 3.12 | **Prod**, verified on device (Epics 1–4, 7, 10 alarms, 11 whatsapp) |
| **Admin web** | `apps/admin` | Next 16 + shadcn + Tailwind v4 + `@supabase/ssr` | **Prod** (leads, team, templates, inventory, builder-ops pages) |
| **Marketing/landing** | `apps/marketing` | Next.js (Luminous template → branded) | **Built** (hero/pricing/footer; testimonials placeholder). Deploy status unconfirmed |
| **Landing demo** | `/demo` route in marketing | React shell iframing ui-redesign HTML | **Built** |
| **Ops console (founder cockpit)** | `apps/ops` | Next 16 + shadcn + Tailwind v4 | **Committed to git `main`** (commit `ad0bbe4`, pushed origin 2026-07-10). Migrations `0090/0091` in git but **NOT yet pushed to prod DB**; no Vercel deploy yet (see §Ops) |
| **Backend / DB** | `supabase/migrations` + `supabase/functions` | Postgres RLS + edge fns (Deno) | **Prod head = migration `0089`** |

---

## Backend state

- **Prod migration head: `0092`** (pushed 2026-07-10). ⚠️ **Migration `0093` (lead read RPCs +
  `customer_code`/`visit_count`, story 13-8-mobile) is authored + applied to LOCAL Docker only — prod
  `supabase db push --linked` of 0093 is PENDING (Rudra runs it).** Sequence recap: 0056 tenant-status chokepoint · 0057–0086 builder-ops + unit CRUD · 0087 cron-secret auth (8.3) · 0088 prepaid billing seam (9.1) · 0089 ops-console backend (9.2) · 0090 ops_list_plans (9.4) + 0091 provision_tenant (9.5) · **0092 hard_tenant_cutoff (9.6) — DONE on prod: guarded `get_my_leads` on tenant status (closes the last un-gated employee read) + relaxed `get_my_billing_status` to any tenant member. Verified: `get_my_leads` has_guard+calls_chokepoint, billing admin-gate removed, live tenant still `active` (guard is a no-op for active/trial).**
  - ⚠️ `platform_admins` is **empty on prod (0 rows)** — until one row (your `auth.uid()`) is inserted, NOBODY can log into the ops console. This is the next unlock. See §Ops "Deploy checkpoint".
- **Billing/lifecycle model (Epic 9, LOCKED):** per-project monthly **prepaid**. Access gated purely on `tenants.status` via `auth_tenant_id()` (0056). Money is collected **out-of-band** (UPI/cash); the app only *records* it. Razorpay is later.
- **The ops RPC surface (0089 + 0090/0091), all `is_platform_admin()`-guarded, audit-logged, RLS-native (NO service-role key in any client):**
  - `ops_list_tenants()` · `ops_list_tenant_payments(tenant)` · `ops_list_audit(limit,offset)` · `ops_list_plans()` (0090)
  - `ops_renew_tenant(tenant,plan,amount,method,note)` → delegates to `renew_tenant()` (9.1 seam)
  - `ops_suspend_tenant(tenant,reason)` · `ops_reactivate_tenant(tenant,note)`
  - `provision_tenant(name,username,password,adminName,plan,start,amount,method,tz)` (0091)
  - `is_platform_admin()` — the one guard; a `platform_admins` row = who may use the console (empty on prod by design).
- **Auth facts to preserve:** admin/employee login goes through the `login` edge fn; plain usernames get the synthetic domain `@employees.nirman.local` in BOTH `public.users.email_or_username` and `auth.users.email`; accounts are dual-store (auth.users + public.users, same `$2a$12` bcrypt — GoTrue + bcryptjs compatible). GoTrue rejects NULL token varchars → they must be `''`.

---

## Ops console (`apps/ops`) — the founder billing/lifecycle + onboarding cockpit

**Stories 9.4 (billing/lifecycle UI) + 9.5 (provision-a-builder), built this session. Dark keyboard-first cockpit (Fira Sans + Fira Code). RLS-native — no service-role key; authority = platform-admin JWT + `is_platform_admin()` re-checked in `proxy.ts`, the `(app)` layout, login, and every RPC.**

Routes / what they do:
- **`/login`** — `signInWithPassword` then `is_platform_admin()` gate; non-admin denied + signed out.
- **`/` (Tenants)** — all tenants, status pills (Active/Trial/Grace/Suspended/Cancelled), relative `paid_until` ("in 4d"/"overdue 2d"), soonest-to-lapse first, red/amber urgency borders, ⌘K filter. Row → right slide-over: billing block, **Record payment / +1mo / +3mo**, Suspend/Reactivate, inline payment ledger. All mutations behind **typed-confirmation** modals (retype tenant name; retype name **and** amount for record-payment).
- **`/provision`** — 3-step wizard (Builder → First admin w/ auto temp password → Plan + Trial/Paid start) → **credential handoff screen** (copyable URL/username/password). Calls `provision_tenant`.
- **`/audit`** — global monospace read-only audit log, newest-first, load-more.

Run it (free/local):
1. Local Supabase stack up (`supabase start` in `nirman-crm/supabase`; Docker). Migrations 0090/0091 must be applied locally.
2. Seed: `apps/ops/scripts/ops-seed.local.sql` (extra tenants + a Quarterly plan + the platform-admin user). Apply: `docker exec -i supabase_db_supabase psql -U postgres -d postgres < apps/ops/scripts/ops-seed.local.sql`.
3. `cd apps/ops && npm run dev` (port 3009). `.env.local` points at `http://127.0.0.1:54321` + local publishable key — **never a service-role key**.
4. **Local creds:** platform admin `ops@nirman.local` / `opsadmin123`. Denied case (a tenant admin, not platform): `admin@nirman.local`.

Verified this session end-to-end via the local API gateway: login gate, tenant list, renew, suspend/reactivate, audit newest-first, anon→401, non-platform-admin→42501, provision→the new builder admin actually signs into GoTrue, audit never stores the password.

Key files: `apps/ops/src/app/{layout,globals.css,(auth)/login,(app)/layout,(app)/page,(app)/audit,(app)/provision}` · `apps/ops/src/components/{ops-sidebar,status-pill,tenant-console,tenant-detail-sheet,confirm-modal,renew-dialog,audit-table,provision-flow}.tsx` · `apps/ops/src/lib/{types,format,utils,supabase/*}.ts`.

### Deploy checkpoint (last updated 2026-07-10) — sale motion = FOUNDER-LED (manual provisioning, no self-serve signup)

Goal: ops console live on the web so Rudra can provision paying builders from anywhere. Progress:

- [x] **Step 1 — Commit + push code.** `apps/ops` + migrations 0090/0091 committed to git `main` (`ad0bbe4`), pushed to origin 2026-07-10. No longer at risk on clean checkout. **DONE.**
- [x] **Step 2 — Push migrations to prod DB.** `supabase db push --linked` applied 0090/0091. Prod head `0091`. Verified `has_list_plans=1 has_provision=1 active_plans=1`. **DONE.**
- [x] **Step 3 — Seed platform admin.** Ops auth user `rudra.pratap.12233@gmail.com` created (dashboard, Auto-Confirm) + inserted into `platform_admins` (uid `9a9dc0ba-cf77-4806-ae66-0c6c81fb5618`, note "founder Rudra"). Verified `admins=1`. Login flow = `signInWithPassword` → `is_platform_admin()` gate. **DONE 2026-07-10.**
- [x] **Step 4 — Deploy apps/ops to Vercel.** DONE 2026-07-10. Separate Vercel project, **same repo** `RudraO2/Nirman-crm`, **Root Directory = `apps/ops`** (npm-workspaces monorepo, single root lockfile; same per-app pattern as admin/marketing). Env (Production): `NEXT_PUBLIC_SUPABASE_URL=https://vhgruadourflpxuzuxfn.supabase.co` + `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<prod anon public>` (NO service-role). Ops console is on the **free `*.vercel.app`** URL by design (founder-only cockpit, no custom domain — GoDaddy domain reserved for customer-facing marketing/admin). Live URL: **<TODO: paste vercel.app URL>**. Prior "internal server error" was env-var related; resolved.
- [ ] **Step 5 — Verify end-to-end on prod URL:** login gate (Rudra's account passes `is_platform_admin`), tenant list loads, provision a test builder, confirm that new builder-admin signs into the mobile/admin app + record a payment. **Login page loads (2026-07-10); full flow verify pending.**

**Tooling note (2026-07-10):** Vercel hosted MCP (`https://mcp.vercel.com`) added to Claude Code **user scope** (`~/.claude.json`). Needs one-time OAuth (`/mcp` → vercel → authenticate) + a session restart to load tools. Once active, an agent can read Vercel build/runtime logs directly instead of guessing.

After Step 5: fully sellable — demo → `/provision` → hand builder their login → collect UPI/cash → record payment in console.

---

## Mobile builder-ops UI (Epics 12–16) — the deferred Flutter screens

Backend for Epics 12–16 is on prod (migrations 0057–0086 + edge fns); only the **mobile screens** were
deferred. Building them now, in the existing single Flutter app `apps/mobile` (NOT a new app — one Play
Store listing), screens surfaced by role tier. Admin web (`apps/admin`) already has these as pages —
use it as the behaviour/parity reference. Following BMAD per story: `bmad-create-story` → `bmad-dev-story`
→ `bmad-code-review`, tested on the **free local Docker** stack (never prod).

### ✅ Slice 1 (demo path) — DONE 2026-07-10
New domain **`apps/mobile/lib/features/inventory/{data,providers,ui}`** (mirrors `features/leads`).
Full demo motion works: **login by role → You tab ▸ WORKSPACE ▸ Availability → project picker → live
colour-coded grid → tap unit → hold for a lead (amber + live countdown) → confirm booking → sold.**

- **14-3-mobile-availability-grid** (done) — grid + Realtime→debounced-refetch-through-RPC
  (`get_project_units`) + read-only detail sheet; margin (`cost_paise`) head-only.
- **15-2-mobile-hold-unit** (done) — Hold action + own-lead picker (`myLeadsProvider`) + CAS `hold_unit`
  + amber flip via authoritative refetch (no optimistic lie) + live countdown (`hold_countdown.dart`,
  reads `unit_holds` directly — tenant-scoped RLS).
- **15-4-mobile-confirm-booking** (done) — Confirm action + payment-verified attestation dialog +
  `confirm_booking` → hold→sold; lead→sold rides the **existing FR-34/7.2 Sold-celebration seam** (no new
  celebration code).
- Wiring: 2 routes in `router/app_router.dart` (`/inventory`, `/inventory/:projectId`) + a WORKSPACE row
  in `features/home/ui/you_screen.dart`. `fake_async` added to dev_dependencies.
- **Gates:** `flutter analyze` 0 errors · full suite **175/175** (32 inventory tests) · guards verified
  LIVE on local Docker via simulated-JWT (margin scoping, hold race/receptionist denial, confirm
  sold/payment/forbidden). **No backend touched. Not committed** (commit when you decide).

### 🔑 Demo seed (LOCAL ONLY — gitignored via `*.local.sql`)
`nirman-crm/supabase/demo-builder-ops.local.sql` seeds role-tiered **loginable** users in tenant
**Nirman Media** (`00000000-0000-0000-0000-000000000001`, owns project **The Velocity**
`e1ebcd6e-321f-491b-bea3-5db3ad34a4cb`, 72 units, 24h hold timer):
- `head@nirman.local` / `demo1234` → `builder_head` (sees margin, confirms)
- `partner@nirman.local` / `demo1234` → `partner_agency` (agency `Skyline Partners`, project shared, NO margin)
- `reception@nirman.local` / `demo1234` → `receptionist` (cannot hold)
- existing `rep1@nirman` = `front_line_rep`; `admin@nirman.local` = super_admin.
Apply: `docker exec -i supabase_db_supabase psql -U postgres -d postgres < supabase/demo-builder-ops.local.sql`.
Dual-store bcrypt recipe mirrors `apps/ops/scripts/ops-seed.local.sql`; `role_tier` stamped in
`raw_app_meta_data` so `auth_role_tier()` reads it from the JWT.

### Key mobile conventions (learned this slice — reuse in Slices 2/3)
- Repo = plain class taking `SupabaseClient`, exposed via `@riverpod` provider; models immutable with
  `fromJson`; providers use codegen → run `dart run build_runner build --delete-conflicting-outputs`.
- **RPC is authoritative; never trust raw Realtime rows** — realtime event → debounced
  `ref.invalidate(provider)` → refetch through the RPC (preserves margin/agency scoping).
- **Do NOT gate correctness on a client-read `role_tier`** — it may be ABSENT from the JWT (12.3 backfill
  not run). Server RPCs enforce; the UI shows what the RPC returns and maps denials to calm messages.
- Colours/theme via `core/theme/app_theme.dart` `AppColors` (never raw hex). UI polish (exact colours,
  animation) can be tuned later — just match the app.
- Verify guards live on local Docker with simulated-JWT SQL (`set local role authenticated; set local
  request.jwt.claims to '{...}'; select rpc(...); rollback;`) — proven pattern.

### Deferred (in `deferred-work.md`, both need a backend RPC — out of demo path)
1. Partner project-picker lists ALL tenant project *names* (can only OPEN shared ones). Needs
   `get_my_projects()` scoping the list per tier.
2. Hold lead-picker is caller-own-leads only; RPC also allows head(any)/leader(subtree). Needs a
   team-scoped lead read (12.5-mobile / `get_team_leads`).

### ✅ Slice 2 (roles) — DONE 2026-07-11
`features/hierarchy` (Organization: user list + tier pills + `set_user_hierarchy` edit + agencies create,
head-only) + `features/team` ("Team leads" via `get_team_leads`, RPC-scoped per tier, sandbox-safe owner
names). Both create→dev→review. Suite 204/204, analyze 0; guards + per-tier scope verified live (sim-JWT).
Stories `12-4-mobile-hierarchy` + `12-6-mobile-team-sandbox` (both `done`). No backend touched.

### ✅ Slice 3 (remaining surfaces) — COMPLETE 2026-07-11
- **✅ 13-4-mobile-reception-verify-visit — DONE 2026-07-11.** New `features/reception` "Reception
  check-in" screen (code → `verify_visit`, RPC-authoritative, uppercase-normalised, PII-minimized shows
  only ordinal+code). Lead-detail surfacing of `customer_code` + visit ordinal via a lightweight
  tenant-scoped direct read (frozen `get_lead_by_id` omits them). 4 new timeline labels. 10 tests, suite
  **214/214**, analyze 0; guards verified live (sim-JWT: reception→visit1 +2 events; rep→permission_denied;
  unknown→invalid_customer_code). Note: create-path 13.2/13.3 mobile UI (secondary phone, budget/config,
  customer-code dialog + wa.me) already existed in `features/leads/ui/new_lead_sheet.dart`. Card-list
  code/ordinal surfacing was deferred — **now DONE by `13-8-mobile-lead-card-code-visit` (2026-07-11):
  migration 0093 adds `customer_code` + `visit_count` to `get_my_leads` (0092 guard preserved) + `get_lead_by_id`;
  LeadCard renders code + ordinal; the 13.4-mobile direct-read shim is retired. LOCAL only — ⚠️ prod `db push` of 0093 PENDING.**
- **✅ 15-5-mobile — booking dashboard — DONE 2026-07-11.** New `features/booking` dashboard: stats tiles
  (confirmed/active/conversion via `get_booking_stats`) + project filter + active-holds list with the
  **reused** `HoldCountdown` + hold→sold via the **reused** `confirm_booking` seam (payment attestation).
  Server-scoped by `visible_user_ids()`. 11 tests, suite **225/225**, analyze 0; verified live (local hold
  seed `demo-booking-holds.local.sql` + sim-JWT): head holds=1 + stats 1/1/2/**50.0%**; rep self=1; rep
  confirm→`forbidden_role`. Agent-filter deferred (needs a roster picker) — deferred-work.md.
- **✅ 16-2-mobile — amendments — DONE 2026-07-11.** New `features/amendments`: "Log amendment" sheet
  (from the booking hold card → `log_amendment`, calm guard errors incl the 0084 lead↔unit link) +
  execution-team surface (`get_amendments_for_execution` PII-free list + per-row lifecycle via
  `set_amendment_status` + head self-join via `add_execution_member`). Lead Timeline `amendment_logged`
  label landed in 13-4-mobile. 18 tests, suite **243/243**, analyze 0; verified live (local seed + sim-JWT):
  head log→created; exec surface 1 PII-free row; req→ack; partner→`forbidden_role`; rep→`not_execution_member`;
  req→done→`invalid_transition`. Deferred: rep-facing log entry + 16.4 FCM push/deep-link (edge fn dormant).

**Slice 3 gates:** `flutter analyze` 0 errors · full suite **243/243** (was 204 after Slice 2: +10
reception, +11 booking, +18 amendments) · all guards verified live on local Docker (simulated JWT). No
backend touched. Local-only seeds `demo-booking-holds.local.sql` + `demo-amendments.local.sql`
(gitignored). **Not committed** (commit after Rudra's on-device look-pass, per Slice 1–2 posture).

## BMAD story records (source of truth = `_bmad-output/implementation-artifacts/sprint-status.yaml`)

- `9-1-prepaid-access-gating-seam` — **done, prod** (0088).
- `9-2-ops-console-backend` — **done, prod** (0089).
- `9-4-ops-console-web-ui` — **review**, local only. Story file: `9-4-ops-console-web-ui.md`.
- `9-5-provision-builder` — **review**, local only. Story file: `9-5-provision-builder.md`.
- Design docs: `9-ops-console-design.md` (§10 UX direction), `9-2-ops-console-backend.md`.
- The two `_bmad-output/` copies (workspace root + `nirman-crm/_bmad-output/`) are synced as of this snapshot.

---

## Next handles (NOT built — names to hand Amelia later)

Ask by story key so a fresh chat has context:
- ~~9.6 tenant-side recharge/lockout screen~~ — **BUILT 2026-07-10 (status `review`, commit `933f647`).** Mobile `features/billing` (repo+provider+`PausedScreen`) gated at `AppShell`; admin web server-layout billing gate + `PausedRecharge`. Server-enforced (0056), UI display-only + fail-open. 10/10 mobile tests, analyze clean, admin tsc+next build green. NO migration. **Left:** device/browser look-pass, live authed AC#1 run on local stack, set real `OperatorContact` support number, then code-review. Story: `9-6-tenant-side-recharge-lockout.md`.
- ~~Commit + deploy the ops console~~ — **Steps 1–4 DONE (see §Ops "Deploy checkpoint"): code pushed ✓, 0090/0091 on prod ✓, platform_admins seeded ✓, Vercel live ✓.** Left = Step 5 (verify login + provision loop on the live URL). Record the vercel.app URL in §Ops (still a TODO).
- **9.7 ops hardening** — enforce MFA/TOTP on login + step-up on suspend/provision; SECURITY DEFINER sweep; optional IP allowlist.
- **Razorpay** — bolts onto `renew_tenant()` (zero rework by design); the mobile "recharge" screen.
- **Mobile builder-ops UI** — Epics 12–16 backend is on prod; the mobile screens were deferred.
- **Landing polish** — real testimonials; confirm marketing deploy.
