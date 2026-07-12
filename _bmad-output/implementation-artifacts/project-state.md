# Project State — what EXISTS (handoff snapshot)

_Last frozen: 2026-07-11. Purpose: a cold-start Amelia (or any agent) reads THIS first to know exactly what is already built, where it lives, and what's live vs local — then picks the next story. This lists what we HAVE. A short "next handles" list at the end names candidate stories to ask for — nothing there is built yet._

Repo: `nirman-crm/` (github.com/RudraO2/Nirman-crm, branch `main`). Supabase prod: `vhgruadourflpxuzuxfn`. Read `nirman-crm/CLAUDE.md` for the hard infra rules (migrations file-based via `db push --linked`, never MCP apply; prod-vs-local footguns).

---

## ⚡ STATE DELTA — 2026-07-12 (read BEFORE the frozen snapshot below)

The snapshot below was frozen 2026-07-11, BEFORE three same-day waves of work. Corrections:

1. **The 🚨 audit banner below is OBSOLETE.** Every robustness-audit finding (4 C + 13 H + 25 M +
   9 L) is FIXED and ON PROD — login is global (0097), leads/units/unit_holds/amendments direct
   access locked (0098/0099), ops MFA server-enforced (0100), plus 0101–0107. Money-path row #10
   is now ✅ (0098/0099 + pgTAP suite pins it). See `robustness-audit-2026-07-11.md` header banner.
2. **Prod migration head = 0111.** Hygiene wave: CI (`.github/workflows/ci.yml`), mobile
   Crashlytics, `scripts/backup-db.ps1` (+ first dump), pgTAP `audit_remediation_invariants`.
   Feature wave: `/demo` merged to main; 8.4 link-based invites (0109 + accept-invite fn +
   `/invite/[token]`); 8.5 email scaffold (`_shared/email.ts`, dormant until `RESEND_API_KEY`) +
   founder demo-request alert (0111); 8.6 starter WhatsApp templates (0108 trigger); 16.4 FCM
   dispatch LIVE (0110 + dispatch-notifications fn, cron verified 200 on prod).
3. Money-path table deltas: #9 operator number is now `--dart-define`-injectable (build-apk.ps1
   reads `.env.local`; placeholder build hides the dead dial buttons) — the REAL number is still
   Rudra's. #5 testimonials still fake. #1/#2/#6/#7/#8 still Rudra/Vercel-side.

## 🎯 PRACTICALITY BACKLOG — 2026-07-12 review (what to build next, in THIS order)

Full-flow practicality review after everything above shipped. The app IS usable end-to-end
(provision → import → invite team → work leads → visit → hold → confirm → sold → recharge).
These are the gaps that will hurt real users, ranked. Nothing here blocks builder #1.

**P0 — before the app is in many reps' hands**
- **Play Store release** (Rudra CONFIRMED 2026-07-12 he'll pay the one-time Play Console fee).
  Checklist: ① 🚨 **generate a real release keystore** — `apps/mobile/android/app/build.gradle.kts`
  line ~31 signs release builds with the DEBUG key (`signingConfigs.getByName("debug")`); Play
  Store will reject it and the signing key is forever — generate + back up a keystore FIRST;
  ② Play Console account + app listing; ③ privacy-policy URL (marketing `/privacy` exists —
  needs Rudra-approved copy); ④ `versionCode` bump discipline per release (pubspec `1.0.0+1`).
- **Offline resilience — Phase 0 (read cache).** Field reps hit dead zones; today the app is
  100% online. Cache the last `get_my_leads` result locally (drift + sqlite are ALREADY app deps)
  and render it with an "offline — last synced X min ago" banner; phone numbers stay tappable
  (voice calls often work when data doesn't). Days of work, biggest practical win per effort.
- **Push-noise guard (16.4 follow-up).** dispatch-notifications pings the whole internal team on
  EVERY `inventory_changed` — including each cron-expired hold's `release`. Busy project ⇒ reps
  disable notifications ⇒ the valuable follow-up alarms die too. Fix: skip `kind='release'`
  events that originate from the expiry sweep (or digest releases to ≤1 push/hour/project);
  keep `new_stock` + manual force-release pings.

**P1 — before builder #5**
- **Offline Phase 1 (write queue).** Queue the 3 hot writes (status change, set follow-up, call
  outcome) locally when offline; replay in order on reconnect. Server guards (LeadReassignedError,
  status transitions) already arbitrate conflicts — client just needs calm "synced/failed" states.
- **Second-admin path.** Invites create employees only; a builder wanting 2 admins needs founder
  SQL today. Either an ops-console "add admin" action or role choice on invites (with guard).
- **Admin password self-recovery.** Employee reset exists (admin-driven); if the ADMIN forgets
  theirs, it's founder-level surgery. Ops-console "reset builder-admin password" button (the
  reset-employee-password fn logic already exists — needs an ops-side caller).
- **Server-side error visibility ritual.** Crashlytics covers mobile; edge-fn/db failures only
  live in Supabase dashboard logs. Free fix: weekly log check ritual + the CI badge; later a
  log-drain. Write the ritual into the ops checklist.

**P2 — quality of life, after real usage data**
- Leader/head read-only web view (platform segregation currently blocks employees from web).
- Per-user notification preferences (mute inventory pings, keep follow-ups).
- Global-username squatting (usernames unique ACROSS tenants since 0097 — fine now, annoying at
  scale; would need per-tenant login namespacing to undo, big change, only if it actually bites).
- WhatsApp Business API (paid) to replace wa.me deep links; Razorpay (parked, per Rudra).
- Brainstorm doc scope: `_bmad-output/brainstorming/brainstorming-session-2026-07-09-2247.md`
  (explicitly parked by Rudra 2026-07-12 — do not action without him).

---

## 💰 MONEY PATH — what blocks first paying builder (read this first)

Definition of done (from §Ops): "demo → `/provision` → hand builder login → collect UPI/cash → record payment in console." Ordered by blocking severity:

🚨 **Read `robustness-audit-2026-07-11.md` (this folder) before touching this list.** A full
multi-agent read-only audit 2026-07-11 found 4 CRITICAL bugs not previously tracked anywhere in
this doc, incl. one that will silently break login for every tenant provisioned after V1
(`supabase/functions/login/index.ts` hard-codes a seed tenant UUID) — i.e. **the first paying
builder provisioned via `/provision` will not be able to log in** until this is fixed. Also 3
tenant-wide RLS/GRANT gaps on `leads`/`units`/`unit_holds`/`amendments` letting any authenticated
tenant employee bypass the entire ownership/hold/booking model via direct REST calls. None of
these are fixed yet — audit findings only, nothing in this doc's "DONE" items below should be
read as covering them (see correction on row 10).

| # | Item | Status | Blocks |
|---|---|---|---|
| 1 | Ops console Step 5 — verify login/tenant-list/provision/payment loop on the **live Vercel URL** (not just local) | ❌ NOT DONE — only login page load confirmed 2026-07-10 | Selling at all — unverified prod ops flow |
| 2 | Record the ops console's live `*.vercel.app` URL | ❌ NOT DONE — never pasted into this doc; re-confirmed 2026-07-11 that it's genuinely unrecoverable from the repo (no `.vercel/`, no `vercel.json`, no CI config, no URL in any commit message) | Rudra can't reach his own tool from a new machine |
| 3 | Push migrations `0093` **+ `0094` + `0095`** to prod (`supabase db push --linked`, one push) | ✅ **DONE 2026-07-11** — all three applied in one `db push`, prod head now `0095`, `supabase migration list` confirms local=remote through 0095 | — |
| 4 | Real pricing numbers (model is locked, ₹ figures deferred) | ❌ NOT DONE | Can't quote a builder |
| 5 | Real testimonials (marketing site still has fake Luminous names — Maya Okonkwo etc) | ❌ NOT DONE — re-confirmed 2026-07-11, `apps/marketing/src/components/luminous/testimonials.tsx` still has "Maya Okonkwo"/"Daniel Rivera"/"Priya Anand", generic agency quotes, stock Unsplash photos | Credibility on first sales call |
| 6 | Point GoDaddy domain at `apps/marketing` | ❌ NOT DONE — marketing deploy status itself unconfirmed | No professional URL to send a lead to |
| 7 | Confirm `apps/marketing` is actually deployed (build was local-verified only) | ❌ UNCONFIRMED — re-checked 2026-07-11, no `.vercel/`/CI/deploy-script evidence in-repo either way; genuinely needs Rudra or Vercel-dashboard access, not resolvable from code | Same as #6 |
| 8 | Vercel env check — no service-role key under `NEXT_PUBLIC_*` (Rudra-only, can't be checked from code) | ⚠️ PARTIALLY CONFIRMED 2026-07-11 — static grep across apps/admin, apps/ops, apps/marketing source + all committed `.env*` files finds zero `SERVICE_ROLE` references anywhere, and zero `NEXT_PUBLIC_`-prefixed secrets. Codebase itself is clean. Still cannot confirm what's actually *set* on Vercel's dashboard (needs Rudra/Vercel access) | PII leak risk before wide sale |
| 9 | Real operator support number (placeholder `910000000000` in `operator_contact.dart`/`operator-contact.ts`) | ❌ NOT DONE — re-confirmed 2026-07-11, still the literal placeholder in both files | Recharge/lockout screen shows fake number to a real lapsed customer |
| 10 | Full `SECURITY DEFINER` sweep (~60 DB fns) | ⚠️ **PARTIAL — scope correction 2026-07-11.** The 2026-07-11 sweep (migration `0094`) covered function-level search_path pinning + EXECUTE grants only and found no vuln in that scope. It did **not** cover table-level RLS/GRANT (the robustness audit's CRITICAL findings — `leads`/`units`/`unit_holds`/`amendments` all grant full INSERT/UPDATE/DELETE to `authenticated` with only tenant-scoped RLS, no ownership/role check) — those are real, unfixed, and outside 0094's scope. See `robustness-audit-2026-07-11.md`. | Security cert before scaling past founder-led trust — **not yet earned** |

**Not blocking money (can ship after first sale):** 9.7 ops MFA/hardening (**MFA/TOTP login core now
BUILT — local/uncommitted; needs prod-dashboard MFA enabled BEFORE deploy or founder lockout — see §"next
handles" 9.7**), Razorpay (deferred — not required per Rudra 2026-07-11), full mobile builder-ops UI polish
(functionally done AND committed, see below — real remaining gap is a stale release APK, not the commit).

---

## Surfaces we have (and where)

| Surface | Path | Stack | Status |
|---|---|---|---|
| **Mobile CRM** | `apps/mobile` | Flutter 3.44 / Dart 3.12 | **Prod**, verified on device (Epics 1–4, 7, 10 alarms, 11 whatsapp) |
| **Admin web** | `apps/admin` | Next 16 + shadcn + Tailwind v4 + `@supabase/ssr` | **Prod** (leads, team, templates, inventory, builder-ops pages) |
| **Marketing/landing** | `apps/marketing` | Next.js (Luminous template → branded) | **Built** (hero/pricing/footer; testimonials placeholder). Deploy status unconfirmed |
| **Landing demo** | `/demo` route in marketing | React shell iframing ui-redesign HTML | **Built** |
| **Ops console (founder cockpit)** | `apps/ops` | Next 16 + shadcn + Tailwind v4 | Code + migrations `0090/0091` **on prod DB + Vercel-deployed** (2026-07-10). **Login-only verified live — full loop (tenant list/provision/payment) on the live URL NOT yet verified** (see §Ops Step 5, §Money Path #1). Live URL itself unrecorded (§Money Path #2) |
| **Backend / DB** | `supabase/migrations` + `supabase/functions` | Postgres RLS + edge fns (Deno) | **Prod head = migration `0096`** (0093/0094/0095/0096 pushed 2026-07-11) |

---

## Backend state

- **Prod migration head: `0096`** (0093+0094+0095 pushed 2026-07-11; **`0096` pushed 2026-07-11 (Amelia),
  prod signature confirmed `get_booking_stats(p_period_days, p_project_id, p_agent_id)`**). `0096`
  (`get_booking_stats` gains `p_agent_id` — booking dashboard agent filter, closes deferred 15.5) uses
  DROP+CREATE (adds a param → would otherwise create an ambiguous overload); `visible_user_ids()` scope
  gate preserved. Verified per-agent via sim-JWT. `0093` = lead read RPCs +
  `customer_code`/`visit_count` (story 13-8-mobile). `0094` = SECURITY DEFINER least-priv grant
  hardening (Money Path #10) — behaviour-preserving, strips dead EXECUTE grants (PUBLIC/anon on
  `create_lead_with_pii`, the 2 amendment-notify trigger fns, and the 3 internal helpers; authenticated
  on the 5 non-RPC fns); owner+service_role keep EXECUTE so every RPC/trigger path is unchanged.
  `0095` = `get_my_projects()` (per-tier project list; closes the 14.3-mobile partner project-picker
  deferred item), verified per-tier via sim-JWT (head/super_admin see all, partner sees agency-shared
  only) prior to push. All three were already live-verified on local Docker before the prod push.
- **Mobile deferred closures 2026-07-11 (Amelia).** ✅ **CORRECTED 2026-07-11 (later same day, Amelia)
  — this whole block was stale: everything below IS committed to `main`** (commit `704e692`,
  confirmed via fresh `git log`/`git status` — zero uncommitted files under `apps/mobile`), and the
  "still deferred" agent-filter item below is also closed. (1) partner
  project-picker — `lead_repository.fetchProjects()` swapped to `get_my_projects` (0095); scopes
  leads/inventory/booking pickers. (2) hold lead-picker widened from own-leads to team scope —
  `hold_lead_picker_sheet.dart` now uses the pre-existing `get_team_leads` (0060) via `teamLeadsProvider`
  + owner labels; NO backend change. (3) booking dashboard agent-level filter (15.5) — **also closed**,
  migration `0096` (`get_booking_stats` gains `p_agent_id`), agent chips + client-side filter. Current
  suite (re-verified fresh 2026-07-11): **268/268 passing, 0 failures**; `flutter analyze`: **0 errors**
  (6 pre-existing warnings + 291 style/info items — "0 issues" was never literally true, only "0 errors").
  Sequence recap: 0056 tenant-status chokepoint · 0057–0086 builder-ops + unit CRUD · 0087 cron-secret auth (8.3) · 0088 prepaid billing seam (9.1) · 0089 ops-console backend (9.2) · 0090 ops_list_plans (9.4) + 0091 provision_tenant (9.5) · **0092 hard_tenant_cutoff (9.6) — DONE on prod: guarded `get_my_leads` on tenant status (closes the last un-gated employee read) + relaxed `get_my_billing_status` to any tenant member. Verified: `get_my_leads` has_guard+calls_chokepoint, billing admin-gate removed, live tenant still `active` (guard is a no-op for active/trial).**
  - ✅ `platform_admins` seeding: this line previously warned "empty on prod (0 rows)" — that was stale
    against this same doc's own §Ops "Deploy checkpoint" Step 3, which is dated 2026-07-10 and says
    `admins=1` verified (uid `9a9dc0ba-cf77-4806-ae66-0c6c81fb5618`, note "founder Rudra"). Trust Step 3:
    seeded, not empty. **Real remaining gap: no release APK reflects any of this.**
    `apps/mobile/build/app/outputs/apk/release/app-release.apk` is dated 2026-07-08 — three days before
    commits `dbe2ee6`/`2921d5a`/`704e692`/`c0f2d84`. `pubspec.yaml` is still `version: 1.0.0+1`, never
    bumped. Need a fresh release build + version bump before this is installable anywhere as "current."
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

**Tooling note (2026-07-10):** Vercel hosted MCP (`https://mcp.vercel.com`) added to Claude Code **user scope** (`~/.claude.json`). Needs one-time OAuth (`/mcp` → vercel → authenticate) + a session restart to load tools. Once active, an agent can read Vercel build/runtime logs directly instead of guessing. **Still not authenticated as of 2026-07-11** — re-checked this session, only the auth-flow tools are exposed, no project/deployment tools yet.

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
  sold/payment/forbidden). **No backend touched.** ✅ Committed 2026-07-11 via `dbe2ee6` (was stale here — verified via `git log`/`git status`, zero uncommitted files under `apps/mobile`).

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
  LeadCard renders code + ordinal; the 13.4-mobile direct-read shim is retired. ✅ Pushed to prod 2026-07-11.**
- **✅ 15-5-mobile — booking dashboard — DONE 2026-07-11.** New `features/booking` dashboard: stats tiles
  (confirmed/active/conversion via `get_booking_stats`) + project filter + active-holds list with the
  **reused** `HoldCountdown` + hold→sold via the **reused** `confirm_booking` seam (payment attestation).
  Server-scoped by `visible_user_ids()`. 11 tests, suite **225/225**, analyze 0; verified live (local hold
  seed `demo-booking-holds.local.sql` + sim-JWT): head holds=1 + stats 1/1/2/**50.0%**; rep self=1; rep
  confirm→`forbidden_role`. **Agent-filter now DONE 2026-07-11 (Amelia):** migration `0096` adds
  `p_agent_id` to `get_booking_stats` (`get_active_holds` already had it); dashboard shows agent chips
  (roster derived from the holds — no roster RPC), client-side list filter + server-side stats per agent.
  +2 widget tests. ✅ `0096` pushed to prod 2026-07-11 (head now 0096).
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
(gitignored). ✅ Committed 2026-07-11 via `dbe2ee6` (was stale here — same correction as Slice 1 above).
Current suite (re-verified fresh 2026-07-11, after later same-day commits too): **268/268**, analyze 0
errors (+291 pre-existing style/info items, +6 pre-existing warnings — unrelated to this diff).

## BMAD story records (source of truth = `_bmad-output/implementation-artifacts/sprint-status.yaml`)

- `9-1-prepaid-access-gating-seam` — **done, prod** (0088).
- `9-2-ops-console-backend` — **done, prod** (0089).
- `9-4-ops-console-web-ui` — **review**, ✅ committed+pushed `ad0bbe4` (2026-07-10) — "local only" here was stale, matches §Ops Deploy checkpoint Step 1. Story file: `9-4-ops-console-web-ui.md`.
- `9-5-provision-builder` — **review**, ✅ committed+pushed `ad0bbe4` (2026-07-10), same correction. Story file: `9-5-provision-builder.md`.
- The 9.7 MFA/step-up bundle (`mfa-step.tsx`, `lib/step-up.ts`, `(app)/layout.tsx`, `(auth)/login/page.tsx`
  changes, local `config.toml` MFA enable) is the one genuinely still-uncommitted piece here — confirmed
  via fresh `git status` 2026-07-11. Held deliberately, ships when Rudra says go. Files read fresh
  2026-07-11 and confirmed complete (proper TOTP enroll/challenge flow, error/loading states, server-side
  AAL2 gate as sole authority) — not a half-written stub.
- Design docs: `9-ops-console-design.md` (§10 UX direction), `9-2-ops-console-backend.md`.
- The two `_bmad-output/` copies (workspace root + `nirman-crm/_bmad-output/`) are synced as of this snapshot.

---

## Next handles (NOT built — names to hand Amelia later)

Ask by story key so a fresh chat has context:
- ~~9.6 tenant-side recharge/lockout screen~~ — **BUILT 2026-07-10 (status `review`, commit `933f647`).** Mobile `features/billing` (repo+provider+`PausedScreen`) gated at `AppShell`; admin web server-layout billing gate + `PausedRecharge`. Server-enforced (0056), UI display-only + fail-open. 10/10 mobile tests, analyze clean, admin tsc+next build green. NO migration. **Left:** device/browser look-pass, live authed AC#1 run on local stack, set real `OperatorContact` support number (still `910000000000` as of 2026-07-11), then code-review. Story: `9-6-tenant-side-recharge-lockout.md`.
- ~~Commit + deploy the ops console~~ — **Steps 1–4 DONE (see §Ops "Deploy checkpoint"): code pushed ✓, 0090/0091 on prod ✓, platform_admins seeded ✓, Vercel live ✓.** Left = Step 5 (verify login + provision loop on the live URL). Record the vercel.app URL in §Ops (still a TODO, confirmed genuinely unrecorded 2026-07-11).
- ~~Mobile builder-ops UI~~ — **Slices 1–3 functionally COMPLETE 2026-07-11, committed (`dbe2ee6` +
  follow-ups), 268/268 tests.** Migrations 0093/0094/0095/0096 all pushed to prod. **Left:** on-device
  look-pass (esp. Story 10.4's OEM auto-start/kill-warning, unverified on real Xiaomi/Oppo/Vivo per its
  own completion notes) + a fresh release build (current APK predates all of this — see §Backend state).
- **9.7 ops hardening** — ✅ **MFA/TOTP on login DONE 2026-07-11 (Amelia), LOCAL/uncommitted.** TOTP is now
  mandatory for the ops console: login page branches after the password + `is_platform_admin` gate into a
  TOTP step (`apps/ops/src/components/mfa-step.tsx` — enroll w/ QR+secret first time, else challenge), and
  the `(app)` server layout requires `getAuthenticatorAssuranceLevel().currentLevel === 'aal2'` else bounces
  to `/login` (authoritative server gate; a not-yet-enrolled admin is driven through enrollment — never a
  dead-end). `next build` green; full flow proven via a scripted TOTP E2E on local Docker (password→aal1,
  enroll, computed-code verify→aal2, gate admits, `is_platform_admin` true, wrong code rejected).
  `supabase/config.toml` `[auth.mfa.totp]` enabled for local dev.
  ✅ **PROD PREREQUISITE — mostly a non-issue:** per Supabase docs, TOTP MFA is **enabled by default on all
  hosted projects** (the `false` in `config.toml` is only the LOCAL CLI default). So prod almost certainly
  needs NO change. Recommended: **verify once** before ops redeploy (Dashboard → Authentication → MFA/Sign-In
  settings → confirm TOTP/App-Authenticator is on; free-tier). The ONLY lockout scenario is if TOTP were
  explicitly disabled on prod — then the aal2 gate bounces forever because `enroll()` fails. If verified on
  (default), just deploy; the code drives enrollment on first login (never a dead-end).
  ✅ **Step-up DONE 2026-07-11 (Amelia, same held ops bundle):** `verifyStepUp()` (`lib/step-up.ts`) runs a
  fresh challenge+verify before the two most destructive actions — **Suspend** (`ConfirmModal requireMfa` →
  a TOTP field on top of the typed-name confirm) and **Provision** (a required authenticator code on the
  final wizard step, verified before `provision_tenant`). `next build` green. **STILL TODO (deferred):**
  optional IP allowlist; step-up on renew/record-payment (lower sensitivity, skipped). SECURITY DEFINER
  sweep already done separately (0094).
- **Razorpay** — bolts onto `renew_tenant()` (zero rework by design); the mobile "recharge" screen.
- **Landing polish** — real testimonials, real pricing numbers, confirm marketing deploy + point domain at it. See §Money Path #4–7.

## Open backend deferred items (re-verified against actual latest migration SQL, 2026-07-11 — none stale)

- **F-2 date-filter off-by-one** — `get_funnel_stats` (latest def: migration `0069`) and
  `get_employee_performance_stats` (latest def: `0054`) both still let `p_days=1` span 2 calendar days
  (unbounded-above date filter / `followup_window` CTE respectively). Confirmed still present, not
  fixed by any later migration.
- **`ERRCODE='42501'` missing** on `permission_denied` in all 6 named functions (`get_builder_home_metrics`,
  `get_employee_activity_stats`, `get_employee_performance_stats`, `get_funnel_stats`,
  `get_lead_status_distribution`, `get_pipeline_activity_14d`) — confirmed still bare `RAISE EXCEPTION`
  with no ERRCODE in their latest definitions (0054/0069).
- **"Active lead" status filter, 3 different formulations** across `get_employee_active_lead_count`,
  `get_employee_active_lead_counts`, `get_employee_performance_stats` — confirmed still inconsistent as
  of migration `0054`.
- **Story 10.4 (alarm OEM hardening) missing from this doc + `deferred-work.md`** — confirmed still absent
  from both as of 2026-07-11 (only lives in `sprint-status.yaml`, status `review`). Its own file's status
  lives as plain body text `Status: review`, not YAML frontmatter.
