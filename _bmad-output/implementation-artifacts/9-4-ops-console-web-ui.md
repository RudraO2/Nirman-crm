# Story 9.4: Platform Ops Console — web UI (founder billing/lifecycle cockpit)

Status: review  <!-- 2026-07-12 (audit M): status text refreshed — committed+pushed to git main (ad0bbe4) 2026-07-10; migrations 0090/0091 ON PROD. Remaining: seed platform_admins row + Vercel deploy (Rudra). Earlier note "FREE/LOCAL only — NOT committed" is obsolete. -->

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## ⚠️ Numbering collision (read first)

`epics.md` § Epic 9 line **9.3** is the mobile **tenant-side "recharge to continue" screen + Razorpay** (design §7 "9.6 app-side lockout" / epics 9.3). Winston's design doc (`9-ops-console-design.md` §7) separately numbers the console work **9.3 scaffold / 9.4 provisioning / 9.5 billing-UI**. To avoid clobbering the epics.md 9.3 slot this story is filed under the distinct key **`9-4-ops-console-web-ui`** (same pattern the P0 security fix used when it collided on "8.3"). It bundles design §7's **9.3 (scaffold + platform-admin auth, MFA scaffolded-only) + 9.5 (billing/lifecycle UI)**. Design §7's **9.4 provisioning** is **explicitly deferred** (needs a `provision_tenant()` backend that does not exist yet — its own story).

## Story

As the platform operator (founder),
I want an isolated, dark, keyboard-first web cockpit that logs me in as a platform admin and lets me triage every tenant's billing state, record a payment / renew, and suspend or reactivate a tenant — each dangerous action behind a typed confirmation — plus browse the immutable audit log,
so that I can run day-to-day billing and lifecycle operations across all tenants on the one hardened surface the 9.2 backend exposes, without ever putting a service-role key in a browser.

## Context & Design Lock (read first)

Story **9.2** (migration `0089`, deployed to prod 2026-07-10) shipped the whole DB seam this UI consumes: `platform_admins` allowlist, append-only `ops_audit_log`, `is_platform_admin()`, and the six platform-admin-guarded RPCs — `ops_list_tenants()`, `ops_renew_tenant()`, `ops_suspend_tenant()`, `ops_reactivate_tenant()`, `ops_list_tenant_payments()`, `ops_list_audit()`. Story 9.1 (`0088`) is the underlying `renew_tenant()` seam.

**Architecture (locked, inherited from 9.2): RLS-native, NO service-role key in any client.** The ops app signs a platform-admin **user** in via Supabase auth (`signInWithPassword`) and calls the guarded RPCs with that JWT. The guard (`is_platform_admin()`) and the audit write live in the database — a client cannot bypass them, and there is no service-role key to leak. This directly contradicts design §3's "service-role key lives ONLY in this deployment's server env" bullet; 9.2 already resolved that in favour of option (b) (guarded SECURITY DEFINER RPCs). We follow 9.2. **Do NOT introduce a service-role key.**

- Source of truth: `nirman-crm/_bmad-output/implementation-artifacts/9-ops-console-design.md` (§3 isolation, §5 fns, §10 UX direction) + `9-2-ops-console-backend.md` (the backend).
- Backend RPC shapes are frozen in `nirman-crm/supabase/migrations/0089_ops_console_backend.sql` — read it, do not re-derive.

## Scope

**IN (this story):**
1. New **separate** Next.js app `apps/ops` (Next 16 + shadcn + Tailwind v4, mirrors `apps/admin`'s config) — a distinct deployment surface, NOT a route in `apps/admin` (design §3 isolation).
2. **Platform-admin login** separate from tenant login: `signInWithPassword`, then gate on `is_platform_admin()`; a non-platform-admin (even a valid tenant admin) is rejected. MFA/TOTP **scaffolded only** (a documented seam), not enforced (deferred to design §7 9.7 hardening).
3. **Tenant list home** (`ops_list_tenants()`): dense table — name, status pill, plan, `paid_until` as relative time ("in 4 days" / "overdue 2d"), soonest-to-lapse first; overdue/expiring rows get a colored left border; a ⌘K-focusable filter box.
4. **Tenant detail right slide-over**: header = name + status + state-dependent primary action; billing block with **Record payment** and **+1 mo / +3 mo** renew chips (`ops_renew_tenant()`); **Suspend / Reactivate** (`ops_suspend_tenant()` / `ops_reactivate_tenant()`); **inline payment ledger** (`ops_list_tenant_payments()`).
5. **Global audit log** view (`ops_list_audit()`): read-only, monospace, newest-first.
6. **Safety rails** (design §10, non-negotiable): typed-confirmation modals on **suspend / reactivate / record-payment** — the operator must retype the tenant name (all three) and the amount (record-payment) before the action fires.

**OUT (explicitly deferred — do NOT build here):**
- Provisioning a NEW builder/tenant + first admin (needs `provision_tenant()` backend — does not exist; design §7 9.4, its own story).
- MFA/TOTP enforcement (scaffold the auth seam only; design §7 9.7).
- Razorpay + the mobile/web tenant-side "recharge to continue" lockout screen (epics.md 9.3 / design §7 9.6 — the warm concierge surface, a different design language).
- Any change to `apps/admin`, `apps/mobile`, or `supabase/**` (backend is done). This story is `apps/ops/**` only.

## Acceptance Criteria

1. **Isolated app.** `apps/ops` is a new Next 16 app added to the root `workspaces`, sharing `apps/admin`'s stack (shadcn/ui, Tailwind v4, `@supabase/ssr`, `radix-ui`, `lucide-react`, `sonner`). It runs against the **local** Docker Supabase stack via `.env.local` (`NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321`, local publishable key) — never prod, never a service-role key. `tsc --noEmit` and `next build` are both clean.

2. **Dark cockpit skin, not the warm tenant style.** Distinct dark, dense, keyboard-first visual system (Retool/Linear/Postgres-admin family) themed entirely via `globals.css` CSS variables + `next/font` (Fira Sans UI + Fira Code mono per ui-ux-pro-max). Reuses NOTHING from the tenant warm-amber lockout style (design §10-B). Status pills use a documented color system (Active green / Trial blue / Grace amber / Suspended red / Cancelled grey).

3. **Platform-admin auth gate (fail-closed).** `/login` does `signInWithPassword`; on success the app confirms `is_platform_admin()` (RPC) is true before granting the console. A user who authenticates but is **not** in `platform_admins` is denied (signed out, shown "not authorised") and lands back on `/login`. Unauthenticated access to any `(app)` route redirects to `/login` (server-side, in `proxy.ts` + a server-component re-check in the app layout). The gate never trusts the client — even a forged cookie hits the DB guard on every RPC.

3b. **MFA seam scaffolded (not enforced).** A `// TODO(9.7): MFA/TOTP step-up` seam is documented at the auth boundary (login success + before suspend/provision per design §10), with no functional TOTP. Its absence is called out in Completion Notes as deferred, not missing-by-accident.

4. **Tenant list home.** `/` renders every tenant from `ops_list_tenants()` in a dense table: **name**, **status pill**, **plan** (`plan_name`, "—" when null), **`paid_until` as relative time** ("in 4 days", "overdue 2d", "—" when null), and `days_remaining`. Rows are **soonest-to-lapse first** (the RPC already orders `paid_until ASC NULLS LAST`; the UI must not reorder away from that). Overdue rows (`days_remaining < 0`) get a red left border; expiring rows (`0 ≤ days_remaining ≤ 7`) an amber one. A filter box, focusable with **⌘K / Ctrl-K**, filters by name/plan/status client-side. Empty and error states are handled (no blank screen).

5. **Tenant detail slide-over.** Clicking a row (or Enter on a focused row) opens a right slide-over: header shows name + status pill + a **state-dependent primary action** (status `active`/`trial`/`grace` → Suspend is destructive-secondary and Record-payment is primary; status `suspended` → **Reactivate** is the primary action; `cancelled` → both offered). A billing block shows plan + `paid_until` + `days_remaining` with **Record payment**, **+1 mo**, **+3 mo** controls. The **payment ledger** for that tenant (`ops_list_tenant_payments()`) renders inline (amount, method, paid_at, covers_from→covers_until, note), newest first, with an empty state. The slide-over is dismissable by Esc and by clicking the scrim.

6. **Guarded mutations + safety rails.** **Record payment / +1mo / +3mo** call `ops_renew_tenant(tenant, plan_id, amount_inr, method, note)`; **Suspend** calls `ops_suspend_tenant(tenant, reason)`; **Reactivate** calls `ops_reactivate_tenant(tenant, note)`. Each of the three is gated behind a **typed-confirmation modal**: the operator must retype the exact tenant **name** to proceed (all three), and for record-payment must also retype the exact **amount** — the confirm button stays disabled until both match. On success: a toast, the slide-over + list re-fetch (fresh status / paid_until / ledger / audit), and the modal closes. On RPC error (`42501` permission_denied, `P0002` tenant_not_found, `plan_not_found_or_inactive`, network) a clear inline/toast error is shown and no optimistic state is left dangling. Buttons disable during the in-flight call (no double-submit).

7. **Global audit log.** `/audit` renders `ops_list_audit()` read-only in a **monospace** table, newest-first (the RPC orders by monotonic `seq DESC`): created_at, actor_user_id, action, target_tenant_id, and formatted `detail` jsonb. No edit/delete affordance exists anywhere (an audit edit control would be an architecture failure, design §10). Pagination or a sane default limit (≤500, the RPC clamps) with a "load more"/offset control; empty state handled.

8. **Free / local-verified.** Verified on the free local Docker stack: a seeded `platform_admins` user logs in and sees **multiple** tenants (cross-tenant proof); recording a payment flips a lapsed tenant to active and appends a ledger + audit row; suspend/reactivate flip status and audit-log; the audit view shows the new rows newest-first; and a seeded **non-platform-admin** auth user is **denied** the console (login gate) and would be denied every RPC (`42501`) even if it reached one. No paid cloud, no Vercel, no prod deploy, no service-role key. Local seeding is a throwaway script/SQL, not committed migration state.

## Tasks / Subtasks

- [ ] **Task 1 — Scaffold `apps/ops`** (AC: 1, 2)
  - [ ] `package.json` (name `ops`, same deps/scripts as `apps/admin`), `next.config.ts`, `tsconfig.json`, `postcss.config.mjs`, `components.json`, `eslint.config.mjs`, `next-env.d.ts`; add `apps/ops` to root `workspaces`.
  - [ ] `.env.local` → local stack URL + local publishable key (gitignored; NO service-role key).
  - [ ] `src/lib/supabase/{client,server}.ts` + `src/lib/utils.ts` (mirror admin).
  - [ ] `src/app/globals.css` — dark cockpit tokens (background/foreground/card/muted/border/primary/destructive + status colors) + Fira Sans/Fira Code via `next/font`.
  - [ ] shadcn UI primitives themed by CSS vars: button, table, badge, input, label, dialog, sheet (slide-over), sonner, card.
- [ ] **Task 2 — Auth gate** (AC: 3, 3b)
  - [ ] `src/proxy.ts` (Next 16 rename of middleware): unauthenticated `(app)` → `/login`.
  - [ ] `(auth)/login/page.tsx`: `signInWithPassword` → `supabase.rpc('is_platform_admin')`; false → signOut + "not authorised".
  - [ ] `(app)/layout.tsx` server component re-checks `is_platform_admin()`; sidebar (Tenants / Audit) + sign-out. MFA TODO seam comment.
- [ ] **Task 3 — Tenant list home** (AC: 4)
  - [ ] `(app)/page.tsx` server fetch `ops_list_tenants()` → client `TenantConsole`. Relative-time + status-pill helpers. ⌘K filter. Colored left borders. Empty/error states.
- [ ] **Task 4 — Tenant detail slide-over + mutations + safety rails** (AC: 5, 6)
  - [ ] Right sheet: header state-dependent action, billing block, +1mo/+3mo/Record-payment, Suspend/Reactivate, inline ledger via client `ops_list_tenant_payments()`.
  - [ ] Typed-confirmation modal (retype name + amount); RPC calls; toast; re-fetch (`router.refresh()` + client re-query); error mapping; in-flight disable.
- [ ] **Task 5 — Audit log** (AC: 7)
  - [ ] `(app)/audit/page.tsx` monospace read-only table; offset "load more"; empty state.
- [ ] **Task 6 — Local seed + verify** (AC: 8)
  - [ ] Throwaway `scripts/ops-local-seed.sql` (local only, NOT a migration): 4–5 extra tenants w/ varied `paid_until`/status, link the plan; create an `ops@nirman.local` auth user (pgcrypto bcrypt) + insert into `platform_admins`; leave `admin@nirman.local` OUT of `platform_admins` (the denied case).
  - [ ] `tsc --noEmit` + `next build` clean. Manually drive: login (allowed + denied), list ≥2 tenants, renew, suspend, reactivate, audit newest-first.
- [ ] **Task 7 — 3-lens review + fix + housekeeping**
  - [ ] Blind Hunter / Edge Case Hunter / Acceptance Auditor; fix findings; record in this file.
  - [ ] Update this story + sprint-status (add `9-4` line; reconcile the drifted root copy up to the nirman copy). Sync both `_bmad-output/` copies.

## Dev Notes

### Non-obvious traps
1. **No service-role key — deliberate.** Design §3 says server-only service-role; 9.2 overruled that with RLS-native guarded RPCs. The browser/SSR client uses only the publishable (anon) key; authority is the platform-admin JWT + `is_platform_admin()`. Introducing a service-role key would re-open the exact hole 9.2 closed.
2. **The list is deliberately cross-tenant.** `ops_list_tenants()` spans ALL tenants — legitimate only because the RPC self-guards. The UI must not add any `auth_tenant_id()`-style scoping.
3. **`paid_until` NULL is a real state,** not an error: the live V1 tenant + trials are never-enrolled (`paid_until` NULL) and must render as "—" / no border, never "overdue".
4. **Relative time must be timezone-safe:** `paid_until` is `timestamptz`; compute against `Date.now()`; the RPC already returns `days_remaining` (server `now()`), prefer it over recomputing to stay consistent with the ordering.
5. **Reactivate ≠ renew (F2 from 9.2):** reactivating a genuinely lapsed tenant is undone by the hourly sweep. The slide-over should steer a lapsed tenant toward **Record payment** (renew) as primary, and treat bare Reactivate as "undo an erroneous suspension". Copy should not promise a lapsed reactivation sticks.
6. **Next 16, not the Next you know:** middleware is `proxy.ts`; read `apps/admin/AGENTS.md`. Mirror admin's `@supabase/ssr` client/server/proxy patterns verbatim.

### Regression guardrails
- Touch **only** `apps/ops/**` + root `package.json` `workspaces` + (housekeeping) the two sprint-status + story files. **No** `supabase/**`, `apps/admin/**`, `apps/mobile/**` changes.
- Do not run against prod. `apps/admin/.env.local` points at PROD by design (CLAUDE.md footgun) — `apps/ops/.env.local` must point at LOCAL.

### Patterns to copy
- `apps/admin/src/lib/supabase/{client,server}.ts`, `src/proxy.ts`, `(app)/layout.tsx`, `(auth)/login/page.tsx`, `components/ui/*`, `globals.css` token structure, `components/nav.ts` sidebar shape.

### RPC contract (from 0089 — frozen)
- `ops_list_tenants() -> {tenant_id uuid, name text, status tenant_status, plan_name text, paid_until timestamptz, days_remaining int}` (ordered `paid_until ASC NULLS LAST, name ASC`).
- `ops_renew_tenant(p_tenant_id uuid, p_plan_id uuid, p_amount_inr int, p_method text, p_note text=null) -> {tenant_id,status,paid_until,payment_id}`. `method ∈ {upi,cash,bank_transfer,razorpay,comp,other}`.
- `ops_suspend_tenant(p_tenant_id uuid, p_reason text=null) -> {tenant_id,status}`; `ops_reactivate_tenant(p_tenant_id uuid, p_note text=null) -> {tenant_id,status}`.
- `ops_list_tenant_payments(p_tenant_id uuid) -> SETOF tenant_payments` (newest paid_at first). Columns: id, tenant_id, plan_id, amount_inr, method, paid_at, covers_from, covers_until, recorded_by, note, created_at.
- `ops_list_audit(p_limit int=100, p_offset int=0) -> SETOF ops_audit_log` (newest seq first). Columns: id, seq, actor_user_id, action, target_tenant_id, detail jsonb, created_at.
- `is_platform_admin() -> boolean`.
- Error codes: `42501` permission_denied, `P0002` tenant_not_found, plan errors raise `P0002`.

### Testing standards
- No unit-test harness for the ops app in scope; verification is `tsc`+`next build` clean + manual drive against the local stack with the seed. (E2E is a later story if desired.)

### References
- [Source: nirman-crm/_bmad-output/implementation-artifacts/9-ops-console-design.md] (§3, §5, §10)
- [Source: nirman-crm/_bmad-output/implementation-artifacts/9-2-ops-console-backend.md] (the backend + RLS-native decision)
- [Source: nirman-crm/supabase/migrations/0089_ops_console_backend.sql] (frozen RPC shapes)
- [Source: nirman-crm/apps/admin/**] (stack + patterns to mirror)
- [Source: nirman-crm/apps/admin/AGENTS.md] ("This is NOT the Next.js you know" — Next 16)

## Dev Agent Record

### Agent Model Used
claude-opus-4-8 (Amelia / bmad-agent-dev, Ralph-loop run)

### Review Findings (3-lens adversarial: Blind Hunter / Edge Case Hunter / Acceptance Auditor — 2026-07-10)

- [x] [Review][Fixed] **F1 (edge — Edge Case Hunter):** the `+1 mo` / `+3 mo` quick chips called `openRenew(1|3)`, and `RenewDialog` fell back to `plans[0]` when no plan of that interval existed — so clicking `+3 mo` with only a 1-month plan would silently record a **1-month** window while the button promised three. **FIX:** the chips are now conditionally rendered from the actual plan catalogue (`planIntervals = new Set(plans.map(p => p.interval_months))`) — a chip appears only when a plan of that interval exists. `tenant-detail-sheet.tsx`.
- [x] [Review][Fixed] **F2 (resilience — Blind Hunter):** the `(app)` server layout treated a **transient** `is_platform_admin()` RPC error the same as an explicit `false` → redirected to `/login?error=not_authorised`, whose `useEffect` **signs the session out**. A momentary DB blip would therefore force-log-out a legitimate operator. **FIX:** split the cases — a bare RPC `error` bounces to `/login` (clean re-auth, no sign-out); only an explicit `isAdmin !== true` uses the `not_authorised` sign-out path. `(app)/layout.tsx`.
- Dismissed as by-design (3):
  - **Suspended tenant's "primary" action is Record-payment, not Reactivate** (design §10 literally says "Suspended→Reactivate"). Intentional deviation grounded in **Story 9.2 finding F2**: a bare reactivate on a genuinely lapsed tenant is undone by the hourly `expire_lapsed_tenants()` sweep. The slide-over therefore surfaces **Record payment** as the primary/blue action + a warning banner steering there, and keeps Reactivate available (outline) for the "undo an erroneous suspension" case. More correct than the pre-F2 design copy.
  - **No service-role key anywhere in `apps/ops`** (design §3 says server-only service-role). Intentional — inherits Story 9.2's RLS-native decision (guarded SECURITY DEFINER RPCs + platform-admin JWT); a service-role key would re-open the exact hole 9.2 closed.
  - **`ops_list_plans()` added as migration 0090** despite "backend done". The UI story surfaced a real gap: the renew form needs a `plan_id` but `plans` is deny-all RLS (0088) and `ops_list_tenants()` exposes only `plan_name`. Minimal additive guarded read, same RLS-native pattern; applied to the LOCAL stack only, flagged as a prod-deploy dependency (below).

### Debug Log References

- Local Docker stack already at 0089 (9.2 verified: `platform_admins`, `ops_audit_log`, all 6 `ops_*` fns present). Applied 0090 (`ops_list_plans`) into the container: `docker exec -i supabase_db_supabase psql -U postgres -d postgres < supabase/migrations/0090_ops_list_plans.sql`.
- Guard sanity (in-txn, `set_config('request.jwt.claims', ...)` + `SET LOCAL role authenticated`): the seeded platform-admin sees **6 tenants** soonest-to-lapse first (Emerald −10, Coral −2, Marigold +4, Skyline +25, Nirman NULL, Trident NULL); `admin@nirman.local` (NOT in `platform_admins`) → `42501 permission_denied` on `ops_list_tenants()`.
- **Full stack verified through the local API gateway (the exact browser client path — anon key + platform-admin JWT + PostgREST RPC):** GoTrue `signInWithPassword('ops@nirman.local')` → 770-char JWT; `is_platform_admin` (`{}` + `application/json`) → `true`; `ops_list_tenants` → 6 rows; `ops_renew_tenant` on suspended Emerald → `{status:active, paid_until:2026-10-10, payment_id:…}`; `ops_list_tenant_payments` → the new ledger row; `ops_suspend_tenant` → suspended; `ops_list_audit` → `seq 7 renew_tenant` newest-first; anon (no JWT) → **401**. App routing: unauth `GET /` → **307 → /login**; `/login` renders "Nirman Ops".
- GoTrue seed trap: a direct `auth.users` INSERT with NULL token varchars (`confirmation_token`, `recovery_token`, `email_change`, `email_change_token_new`) makes GoTrue return `500 "Database error querying schema"` — its Go scanner cannot read NULL into those string columns. They MUST be `''`. Baked into the seed.
- `tsc --noEmit` clean; `next build` clean (routes `/`, `/audit`, `/login` + Proxy middleware) before and after the F1/F2 fixes.

### Completion Notes List

- Built **`apps/ops`** — a new, isolated Next 16 + shadcn + Tailwind v4 app (mirrors `apps/admin`'s stack) consuming the Story 9.2 backend. **All 8 ACs verified** on the free local Docker stack.
- **Architecture honoured:** RLS-native, **no service-role key** — browser/SSR use only the publishable key; authority is the platform-admin JWT + `is_platform_admin()`, re-checked in `proxy.ts`, the `(app)` server layout, the login flow, and (definitively) every RPC.
- **Dark founder cockpit** per ui-ux-pro-max (Dark-OLED style, Fira Sans + Fira Code): dense table home, status-pill system (Active/Trial/Grace/Suspended/Cancelled), relative `paid_until`, ⌘K filter, right slide-over detail w/ inline ledger, +1/+3mo renew chips, and **typed-confirmation** safety rails (retype tenant name on suspend/reactivate; retype name **and** amount on record-payment). Global monospace read-only audit view with load-more. Shares nothing with the warm tenant-lockout style.
- **MFA (9.7) scaffolded only:** `TODO(9.7)` seams at both auth boundaries (login success + `(app)` layout); no functional TOTP by design.
- **NOT done (out of scope / deferred):** provisioning a new tenant (needs `provision_tenant()`), MFA enforcement, Razorpay + tenant-side recharge screen. No `apps/admin` / `apps/mobile` changes.
- **Prod-deploy dependencies (when this ships — NOT done here, FREE/LOCAL only):** (1) `supabase db push --linked` migration **0090** (`ops_list_plans`) — 0090 is applied to the LOCAL stack only; the ops app's renew form needs it. (2) `INSERT INTO public.platform_admins (user_id) VALUES ('<operator auth.uid()>')` on prod (seeded empty by design). (3) point `apps/ops/.env.local` at prod URL + prod publishable key (NEVER a service-role key). (4) separate Vercel project on the `ops.<domain>` subdomain (design §3). None performed — no git commit, no push, no cloud.
- **Local test creds:** `ops@nirman.local` / `opsadmin123` (platform admin); `admin@nirman.local` intentionally left OUT of `platform_admins` (the denied case). Seed: `apps/ops/scripts/ops-seed.local.sql` (throwaway, gitignored).

### File List

**NEW — `nirman-crm/apps/ops/` (the app):**
- Config: `package.json`, `next.config.ts`, `tsconfig.json`, `postcss.config.mjs`, `eslint.config.mjs`, `components.json`, `next-env.d.ts`, `.gitignore`, `.env.local` (gitignored, local only)
- `src/app/globals.css` (dark cockpit tokens), `src/app/layout.tsx` (Fira fonts), `src/proxy.ts` (auth gate)
- `src/lib/utils.ts`, `src/lib/types.ts`, `src/lib/format.ts`, `src/lib/supabase/{client,server}.ts`
- `src/components/ui/{button,input,label,textarea,table,badge,dialog,sheet,sonner}.tsx`
- `src/components/{ops-sidebar,status-pill,tenant-console,tenant-detail-sheet,confirm-modal,renew-dialog,audit-table}.tsx`
- `src/app/(auth)/login/page.tsx`
- `src/app/(app)/layout.tsx`, `src/app/(app)/page.tsx` (tenants home), `src/app/(app)/audit/page.tsx`
- `scripts/ops-seed.local.sql` (throwaway local seed — gitignored)

**NEW — backend (discovered UI dependency; LOCAL-applied, NOT pushed):**
- `nirman-crm/supabase/migrations/0090_ops_list_plans.sql`

**MODIFIED:**
- `nirman-crm/package.json` (added `apps/ops` to `workspaces`)
- `_bmad-output/implementation-artifacts/9-4-ops-console-web-ui.md` (this story) + `sprint-status.yaml` (9-4 line; reconciled the drifted root copy up to the nirman copy)
- `nirman-crm/_bmad-output/implementation-artifacts/{9-4-…md, sprint-status.yaml}` (synced copies)

## Change Log
- 2026-07-10 — Story 9.4 drafted: ops console web UI (`apps/ops`), consuming the 9.2 backend (0089). Filed under `9-4` to avoid the epics.md 9.3 (mobile recharge) collision. Status → ready-for-dev.
- 2026-07-10 — Ralph-loop run (write → code → 3-lens review → fix): built `apps/ops` (Next 16 + shadcn + Tailwind v4), dark cockpit, platform-admin login, tenant list, detail slide-over w/ typed-confirmation mutations, audit view. Added migration `0090_ops_list_plans` (discovered UI dependency, local only). Verified all 8 ACs on the free local stack via the API gateway; `tsc` + `next build` clean. 3-lens review → F1 (dishonest quick-chip fallback) + F2 (transient-error force-logout) fixed, 3 dismissed by-design. FREE/LOCAL — not committed, not pushed. Status → review.
