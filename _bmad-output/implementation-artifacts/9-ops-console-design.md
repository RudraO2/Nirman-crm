# Epic 9 — Platform Ops Console (superadmin) + Subscription/Entitlement

**Status:** design · **Author:** Winston (2026-07-09) · **Depends on:** 8.3 deployed (edge auth hardened)
**Decisions locked:** founder-provisioned onboarding (NO public self-serve signup); manual billing (NO Razorpay/autopay/GST yet — deferred); isolated hardened ops app.

---

## 1. Purpose

The one surface that crosses ALL tenants: the founder provisions builders, sets plans, records out-of-band payments, and gates access. Reuses the existing fail-closed `tenants.status` chokepoint (migration 0056) so gating is a data-layer flip, not new enforcement.

## 2. Onboarding model (locked)

**Founder-provisioned (assisted).** Flow:
1. Founder closes a builder in person.
2. In the ops console: create tenant + first admin account, pick plan.
3. Hand credentials → builder signs into web admin (existing `apps/admin`) on the domain.
4. Builder/associate adds sub-associates → each installs the mobile app (Play internal-testing link).
5. Founder collects payment out-of-band (UPI/cash) → console "mark paid" → `status=active`, `paid_until` set.
6. Month-end unpaid → cron flips `active→suspended` → floor freezes → recharge to restore.

No public signup endpoint exists (security + market fit). Self-serve deferred.

## 3. Deployment / isolation (hardened)

- **Separate deployment** (own Vercel project + subdomain, e.g. `ops.<domain>`), NOT a route in `apps/admin`. Distinct from the tenant apps.
- **Service-role key lives ONLY in this deployment's server env** (never `NEXT_PUBLIC_*`, never in mobile/admin).
- **Own auth**, separate from tenant login: allowlisted platform-admin accounts only + **MFA/TOTP required**.
- **All privileged actions go through server-side handlers / edge fns** that (a) re-verify the caller is a platform admin, (b) write an `ops_audit_log` row. No direct client-side service-role use.
- Optional: IP allowlist / Vercel deployment protection on the ops subdomain.

## 4. Data model (additions; reuse existing tenants + 0056 status)

Next migration files after `0086`:

- `tenants` += `paid_until timestamptz`, `plan_id uuid REFERENCES plans(id)`, `grace_days int NOT NULL DEFAULT 3`.
- `plans` — `id, name, monthly_price_placeholder, quota_minutes, quota_messages, is_active`. (Prices placeholder; per-project billing.)
- `tenant_payments` — append-only ledger: `id, tenant_id, amount, method (upi|cash|bank|trust|other), period_start, period_end, recorded_by (platform_admin), note, created_at`.
- `platform_admins` — `user_id` allowlist of who may use the console (separate from tenant `users`). NOT tenant-scoped.
- `ops_audit_log` — `id, actor (platform_admin), action, target_tenant_id, detail jsonb, created_at`.

## 5. Core functions (the seam)

- **`renew_tenant(p_tenant, p_until, p_plan)`** — SECURITY DEFINER, platform-admin-guarded: sets `paid_until`, `plan_id`, flips `status=active`, inserts `tenant_payments` + `ops_audit_log`. **This is the single seam** — a future Razorpay webhook calls the same fn; manual "mark paid" calls it too. No access-control rework when autopay lands.
- **`suspend_tenant(p_tenant, p_reason)`** / **`reactivate_tenant`** — guarded, audit-logged.
- **`provision_tenant(p_name, p_admin_login, ...)`** — creates tenant (`status=trial` or `active`), first admin (mirrors `bootstrap-admin` dual-store pattern: `auth.users` + `public.users`), audit-logged.
- **`expire_overdue_tenants()`** — pg_cron daily: `status='active' AND paid_until + grace_days < now()` → `suspended`. Soft-grace window before hard freeze.
- **`get_my_billing_status()`** — readable EVEN when suspended (bypasses the gate for own tenant only) so the app can render a friendly "recharge" screen instead of a blank/broken UI.
- All platform-admin guards: `EXISTS (SELECT 1 FROM platform_admins WHERE user_id = auth.uid())`.

## 6. App-side gating (tenant apps)

- On load, tenant apps call `get_my_billing_status()`. If `suspended`/`expired` → full-screen **"Recharge to continue — contact us"** (mobile Flutter + web admin). Grace window (paid_until < now < paid_until+grace) → working + a persistent "payment due" banner.
- Actual data denial already enforced by `auth_tenant_id()` returning NULL for non-active tenants — the screen is UX, the DB is the real gate.

## 7. Story breakdown (build order)

- **9.1** — Schema: `plans`, `tenant_payments`, `platform_admins`, `ops_audit_log`, `tenants` billing columns. (migration after 0086)
- **9.2** — Fns + cron: `renew_tenant`, `suspend/reactivate`, `provision_tenant`, `expire_overdue_tenants` (pg_cron), `get_my_billing_status`. All platform-admin-guarded + audit-logged.
- **9.3** — Ops app scaffold: separate deployment, platform-admin auth + MFA, service-role server-only, gating middleware.
- **9.4** — Provisioning UI: create builder tenant + first admin, set plan.
- **9.5** — Billing UI: list all tenants (status, paid_until), mark-paid/extend, suspend/reactivate, view payment ledger + audit log.
- **9.6** — App-side lockout: friendly recharge screen (mobile + web) via `get_my_billing_status`; grace banner.
- **9.7** — Hardening pass: MFA enforced, audit coverage, secret handling verified, optional IP allowlist; security test.

## 8. Out of scope (deferred)

- Razorpay / UPI Autopay / eNACH (no GST yet) — bolts onto `renew_tenant()` later, zero rework.
- Public self-serve signup.
- Automation quota *enforcement* (tables designed in 9.1, metering enforced in a later story).

## 9. Conventions

File-based migrations after `0086`, `supabase db push --linked`, never MCP apply. Edge fns `--no-verify-jwt` MUST use the auth guards from Story 8.3 (`_shared/serviceAuth.ts`) or platform-admin JWT checks. Update CLAUDE.md when shipped.

## 10. UX direction (Winston + Sally party-mode consensus, 2026-07-09)

**Two opposite design languages, same billing backend — never mix them.**

**A) Ops console = dense founder cockpit** (internal, one user, efficiency + safety over polish):
- Shell: persistent left nav + table-driven main + **right slide-over detail pane**. Dark-mode-native, keyboard-first, zero onboarding.
- **Calm-dense principle:** high density on READ surfaces, deliberate friction on WRITE surfaces. Don't treat every screen alike.
- **Tenant list (home):** data table — builder, plan, status pill (Active/Trial/Suspended/Grace), `paid_until` as relative ("in 4 days"/"overdue 2d"), MRR. Sortable/filterable. Search box doubles as **⌘K command palette**. Overdue/expiring rows get a colored left border. Morning-triage screen.
- **Provision new builder:** dedicated route (not modal) — builder details → first admin → plan + initial `paid_until`; ends on a **success screen showing the admin credentials/invite to hand off** (not a toast).
- **Tenant detail:** right slide-over (expandable to full page); header = name + status + state-dependent primary action (Suspended→Reactivate; Active→Record payment/Extend); billing block with "+1mo/+3mo" chips; **payment ledger inline**.
- **Audit log:** global, immutable, filterable, monospace, read-only. Audit global; payments per-tenant.
- **Safety rails = the security model at the UI layer (non-negotiable):** typed-confirmation modals on **suspend / reactivate / record-payment** (confirm tenant name + amount); **MFA step-up** on **suspend** and **provision**; audit rows never editable/deletable from the UI (an edit affordance there = architecture failure).

**B) Tenant-side lockout / "recharge to continue" = warm Hindi concierge** (non-techy Jaipur builder, locked out, anxious — shown in apps/admin web + apps/mobile Flutter):
- **Reuse NOTHING from the ops console.** One hero line (Hindi-first, e.g. "आपका खाता कुछ समय के लिए रुका है — रिचार्ज करके तुरंत जारी रखें।"), the amount due, a UPI QR / "contact us" path, one big tap target (esp. mobile).
- **Color = warm amber/blue "paused, recoverable" — NOT red** (red reads as deleted/error and spikes panic). Reassure data is safe, not deleted. Zero jargon ("tenant", "suspended", "grace period" all banned from this screen).

Build with `ui-ux-pro-max` / `impeccable` / shadcn/ui. Visual skin for the cockpit: Retool/Linear/Postgres-admin family (dense, not Notion-calm).
