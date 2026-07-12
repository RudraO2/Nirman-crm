# Robustness / Completeness Audit — 2026-07-11

Read-only, multi-agent audit across all 5 surfaces (apps/mobile, apps/admin, apps/ops,
apps/marketing, supabase/migrations+functions), each finding independently adversarially
re-verified against actual source before inclusion. Nothing was fixed, committed, or
written to any database as part of this audit — findings only.

**Process:** 7 parallel finder agents (mobile / admin / ops / marketing / db-security /
concurrency / doc-drift) surfaced 59 candidate findings. Every candidate was re-checked by
a separate agent instructed to read the actual file and try to refute it (2 refuted,
dropped). Every CONFIRMED/ADJUSTED critical or high finding then got a second, independent
refutation pass before being trusted (0 dropped on that pass). 57 findings survived.

---

## 🔴 CRITICAL (4) — fix before onboarding any paying customer

### C1. Login is hard-coded to a single seed tenant — every tenant provisioned after V1 cannot log in, on web or mobile
`supabase/functions/login/index.ts:19, 72-77`

`SEED_TENANT_ID = "00000000-0000-0000-0000-000000000001"` is baked into the login
function's user lookup (`.eq("tenant_id", SEED_TENANT_ID)`), and this is the *only*
function both `apps/admin` and `apps/mobile` call to authenticate. `provision_tenant`
(0091) correctly generates a fresh UUID per new tenant. The moment the ops console
provisions the first real paying builder, that admin's login (and every employee's)
returns 401 "Invalid username or password," with zero workaround short of a code fix +
redeploy. **This will silently kill the first sale.**

Related design note (medium, folded in here): beyond the hardcode, the whole login
design assumes a single global tenant (username lookup keyed only by
`email_or_username` within one hardcoded tenant_id), which is architecturally
incompatible with the per-tenant unique index actually defined on `public.users`.

### C2. `leads` table RLS is tenant-wide only — any employee can read/reassign/delete any other agent's leads directly via the REST API
`supabase/migrations/0009_create_leads.sql:172-182`

The policy only checks `tenant_id = auth_tenant_id()`; ownership/hierarchy (rep sees
own, leader sees subtree) exists *only* inside RPCs like `get_my_leads`/`assign_lead`.
A front_line_rep or receptionist can call `supabase.from('leads').select('*')` or
`.update()`/`.delete()` directly with their own JWT and bypass ownership checks, status
guards, and audit logging entirely — in a commission sales org this is a live
lead-theft/sabotage vector, i.e. it can move real commission money.

### C3. `units` table grants full INSERT/UPDATE/DELETE to any tenant user, RLS-scoped only by tenant — the entire hold→confirm→sold protocol is bypassable
`supabase/migrations/0070_inventory.sql:92-102`

No role check exists at the table level. Any authenticated tenant user (including a
receptionist, whom `hold_unit` explicitly forbids from holding units) can `PATCH` a
unit's status straight to `sold` via REST, with no ownership check, no payment
verification, no active hold required. Verified concrete failure modes: (a) two people
can end up "selling" the same physical unit to two different leads; (b) a sale can
happen with no `confirm_booking` call — no payment-verified record, no audit trail.
Given real property inventory and commission money, this is the single highest-impact
gap found.

### C4. `unit_holds` table has the same tenant-wide full-grant issue — holds can be forged, resurrected, or deleted outside `hold_unit`'s guards
`supabase/migrations/0075_unit_holds.sql:53-60`

A user can directly delete a competing agent's active hold (clearing the
unique-active-hold index) then hold the unit themselves — hijacking someone else's
in-progress deal — or resurrect an expired/converted hold, or fabricate one for any
unit/lead pair, skipping `hold_unit`'s receptionist-denial/ownership/verified-visit
checks entirely. Compounds C3. (Independently corroborated by a second finder lens —
db-security — flagging the same tenant-wide grant on `unit_holds` from the read/audit
angle.)

---

## 🟠 HIGH (13)

1. **Ops MFA "step-up" (Story 9.7) is enforced only in the browser — the RPCs never
   check it.** `apps/ops/src/lib/step-up.ts:1-29` + `supabase/migrations/0089_ops_console_backend.sql`.
   `verifyStepUp()` re-confirms TOTP but by its own comment "does not change the
   session's AAL" — and `ops_suspend_tenant`/`ops_reactivate_tenant`/`ops_renew_tenant`/
   `provision_tenant` guard only on `is_platform_admin()`. Anyone holding a valid
   platform-admin JWT (stolen session, XSS, unlocked laptop) can call these RPCs
   directly via curl with zero TOTP — defeating the entire point of the step-up
   feature for suspending real tenants or minting new paying-tenant admin accounts.
2. **`amendments` table has the same tenant-wide full-grant issue as units/unit_holds**,
   bypassing `log_amendment`/`set_amendment_status`'s role and lifecycle guards.
   `supabase/migrations/0080_amendments.sql:42-48`
3. **`units.cost_paise` (margin/profit data) is readable by any authenticated tenant
   member via direct REST** — the app hides it only inside the `get_project_units` RPC,
   not at the DB level. A partner_agency account (still `authenticated`) can read every
   unit's true margin. `supabase/migrations/0070_inventory.sql:68-102`
4. **`phone_hash` is an unsalted SHA-256 digest over the ~4-billion-number Indian mobile
   keyspace** — brute-forceable in hours, which combined with C2 means anyone can
   recover every customer's real phone number, making the `pgp_sym_encrypt` on the
   phone column moot. `supabase/functions/create-lead/index.ts:41-48,142-146,167`
5. **`confirm_booking` has no ownership/subtree scoping for `team_leader`** — any
   team_leader in the tenant can confirm ANY hold, even one entirely outside their
   reporting line, misattributing another team's real sale.
   `supabase/migrations/0078_confirm_booking.sql:42-45`
6. **`renew_tenant`/`ops_renew_tenant` has no idempotency protection** — a double-click
   or client retry on "Record Payment" creates a second ledger row and double-extends
   `paid_until` for one real collection (row-lock only prevents lost-update, not a
   second sequential call). `supabase/migrations/0088_prepaid_billing.sql:87-148` —
   flagged independently by both the concurrency and ops lenses.
7. **Admin "Add tower" is completely broken** — the insert omits the NOT NULL
   `tenant_id` column, so it fails every time, blocking a basic pre-sale inventory setup
   step. `apps/admin/src/app/(app)/inventory/inventory-client.tsx:253-269`
8. **Mobile swipe-to-mark-dead always dismisses the card even if the RPC fails** — a
   live lead can silently vanish from a rep's list with zero server-side effect and no
   error surfaced. `apps/mobile/lib/features/home/ui/home_screen.dart:124-156,285-291`
9. **Ops provisioning success screen shows the literal placeholder text "your builder
   admin URL"** instead of the real sign-in link, on every single provisioning —
   guaranteed to happen on the very first live onboarding.
   `apps/ops/src/components/provision-flow.tsx:129`
10. **The marketing site's only lead-capture form ("Book a demo") has no
    `onSubmit`/`action`** — it's not even a client component. Every prospect who
    submits loses their info silently with no error. This is the target of every CTA on
    the page. `apps/marketing/src/components/luminous/footer.tsx:30-42`
11. **`epics.md` still contains a contradictory Epic 9 description** — the skim-first
    "Epic List" summary still describes the abandoned Stripe per-seat model; the real
    shipped per-project-prepaid model only appears ~900 lines later. A future agent
    skimming the top could build the wrong billing system.
    `_bmad-output/planning-artifacts/epics.md:179-180 vs 1102-1121`
12. **`sprint-status.yaml` (documented single source of truth) has zero entries for
    migrations 0094/0095/0096**, all on prod per commit `704e692`. Risk of redoing
    closed work or reusing migration numbers.
13. **`sprint-status.yaml` marks 7 mobile builder-ops stories "NOT committed"** when git
    shows them committed same-day (`dbe2ee6`) — risk of an agent distrusting or re-doing
    already-shipped, tested mobile UI.

---

## 🟡 MEDIUM (25)

| File:line | Issue |
|---|---|
| `apps/mobile/lib/features/leads/ui/new_lead_sheet.dart:139-144`, `edit_lead_sheet.dart:137-139`, `reschedule_visit_sheet.dart:45-52` | Raw exception `.toString()` shown directly to users on the 3 highest-frequency mobile write paths, unlike the calm-mapping convention used everywhere else |
| `apps/mobile/lib/features/booking/ui/booking_dashboard_screen.dart:49-70,404-490` | "Convert to sold" has no double-tap guard (unlike the identical action elsewhere); RPC backstops it so no double-sale, just a wasted round-trip |
| `apps/mobile/lib/core/config/operator_contact.dart:1-20` | Support number on the real lockout/recharge screen is still the literal placeholder `910000000000`, no build-time check |
| `apps/mobile/lib/features/alarms/data/alarm_scheduler.dart:304-339` | Customer's real name is put into the OS notification title + native alarm-plugin storage as plaintext |
| `apps/mobile/lib/features/amendments/ui/amendments_execution_screen.dart:37-58,266-295` | Amendment status buttons have no in-flight guard (server's transition-validation prevents real damage, just a confusing double error toast) |
| `apps/mobile/lib/features/inventory/data/inventory_repository.dart:160-172` | `p_payment_verified` is hardcoded `true` client-side regardless of the UI checkbox — the RPC has zero independent evidence a payment happened, purely a UI affordance |
| `apps/admin/src/app/(app)/holds/page.tsx:9-16` | Silently swallows a failed projects query (no `error` check) — inconsistent with sibling pages |
| `apps/ops/src/components/tenant-detail-sheet.tsx:270-280` + `renew-dialog.tsx` | Reactivate and Record Payment require **no** MFA step-up at all, unlike Suspend/Provision — flagged by both the ops and concurrency lenses |
| `apps/ops/src/components/confirm-modal.tsx:96-110` | Typed-confirmation rail defeated by simply copy-pasting the tenant name shown right next to the input |
| `apps/ops/src/components/provision-flow.tsx:19-25` | New tenant admin's temp password generated with `Math.random()` (non-cryptographic PRNG) |
| `apps/ops/src/components/provision-flow.tsx:140` | "Provision another" resets name/username/password but leaves stale amount/method/plan/mfaCode from the last builder — risk of the next tenant's first payment being recorded with the wrong amount |
| `apps/marketing/src/components/luminous/footer.tsx:46-86` | All footer nav links, social icons, and Privacy/Terms links are dead anchors (`#top`/`#footer`) |
| `apps/marketing/src/components/luminous/footer.tsx:14` | Footer background image hosted on an unrelated third-party Supabase project's public bucket, not Nirman infra |
| `apps/marketing/src/components/sections/*` (8 files) + `site-header.tsx`/`site-footer.tsx` | A second, complete, entirely unreferenced landing-page implementation sitting dead in the tree |
| `.claude/worktrees/demo-showroom/.../demo/page.tsx:1-13` | The interactive `/demo` showroom only exists on an unmerged branch/worktree — main has no `/demo` route despite CTAs implying one |
| `supabase/migrations/0094_security_definer_grant_hardening.sql:1-16` | The migration's own "NO live vulnerability" audit never covered table-level GRANT/RLS — exactly where C2/C3/H3 live |
| `supabase/migrations/0078_confirm_booking.sql:51-62` | Doesn't check `unit_holds.expires_at` — a hold that's technically lapsed but not yet swept by the once-a-minute cron can still be confirmed |
| `supabase/migrations/0074_inventory_change_guard.sql:160-165` | `force_release` reverts a sold unit to available without reconciling the hold row or lead status — latent double-sale of the same unit |
| `_bmad-output/implementation-artifacts/9-4-ops-console-web-ui.md:3` | Stale pre-launch status text contradicted by git/sprint-status.yaml |
| `_bmad-output/implementation-artifacts/story-6.1-bulk-import.md:4` | Stale "in_progress" status contradicted by git/sprint-status.yaml |
| `apps/admin/src/app/(app)/holds/holds-client.tsx:1-429` | No route-level `error.tsx` anywhere under `apps/admin/src/app/(app)/`, and 12 of 15 route segments have no `loading.tsx` — bumped from low on recheck given it spans money-moving pages |

---

## ⚪ LOW (9)

- `apps/mobile/lib/features/leads/ui/archived_screen.dart:98-104` — raw exception on a read path (retry-safe, no data loss)
- `apps/mobile/lib/features/leads/ui/share_lead_sheet.dart:32-51,150-196` — concurrent-tap allows parallel shares (idempotent, harmless)
- `apps/admin/src/app/(app)/holds/holds-client.tsx:150-162` — force-release always passes `p_expected_version: null`, skipping the optimistic-concurrency check
- `apps/ops/src/components/renew-dialog.tsx:48-54` — quick-chip plan selection silently picks the first match on ambiguous intervals
- `supabase/migrations/0089_ops_console_backend.sql:187-233` — `ops_reactivate_tenant` flips *any* non-active tenant (incl. genuinely cancelled ones) straight to active
- `supabase/migrations/0091_provision_tenant.sql:82-119` — username-uniqueness check is a TOCTOU relying on an unverified DB constraint
- `apps/marketing/src/components/luminous/nav.tsx:3-9,22-27` — hardcoded active-nav-item, no scroll-spy
- `apps/marketing/src/components/luminous/dashboard.tsx:217` — mockup shows a fake domain (`crm.nirmanmedia.com`) inconsistent with the real one (`app.nirman.in`)
- `apps/marketing/src/components/*` (~22 files: AnimatedContent, Beams, ClickSpark, etc.) — unused WebGL/animation effect components confirming the "removed for lag" cleanup was clean at the render level but left dead files/deps behind
- `_bmad-output/implementation-artifacts/12-4-builder-head-manages-hierarchy.md:3` — stale "deferred" doc note; migration 0059 has been on prod since 2026-07-07

**Also checked and confirmed already correctly fixed (no action needed):**
`apps/admin/src/components/import/import-wizard.tsx:75-90` — the import-wizard's dupe-check
race and stale-file-input bugs — both fixes hold up under adversarial re-read.

---

## Bottom line

Nothing was fixed, committed, or touched in the DB — findings only. Recommended order:
**C1 first** (login lockout will break the first sale outright), then **C2–C4** (tenant-wide
table grants on leads/units/unit_holds/amendments — exploitable with just a valid JWT and a
REST client, no UI bug needed), then the HIGH list.
