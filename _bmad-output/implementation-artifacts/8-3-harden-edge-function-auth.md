# Story 8.3 — Harden `verify_jwt=false` Edge Function auth

**Status:** in-review · **Epic:** 8 (Security hardening) · **Raised by:** Winston (security review 2026-07-09)
**Priority:** P0 — pre-launch must-fix (exploitable unauthenticated endpoints running with service-role)
**Migration:** none (edge-function + pg_cron job changes only)

---

## Problem (the finding)

Seven Edge Functions are deployed `verify_jwt = false`, so Supabase's gateway does **not** authenticate the caller — the function must do it itself. **None of them actually do.** Their URLs are public (`https://<project>.functions.supabase.co/<name>`) and the project ref ships in the client, so they are reachable by anyone.

- **Four "admin-invoked" fns** check only `auth.startsWith('Bearer ')` — they never compare the token to the service-role key, then run with `SUPABASE_SERVICE_ROLE_KEY` internally (RLS bypassed):
  - `send-developer-update`
  - `send-assignment-notification`
  - `send-bulk-assignment-notification`
  - `send-amendment-notification`
- **Three "cron-invoked" fns** have **no** Authorization check at all:
  - `process-overdue-followups`
  - `send-followup-notifications`
  - `streak-at-risk`

**Blast radius (why P0 but not Critical):** No lead PII is returned to the caller (responses are `{sent, recipients}` only, pushes go to the tenant's own devices). But an unauthenticated attacker can, for **any tenant**: trigger push-notification spam, force repeated overdue/followup processing (FCM + DB cost abuse), and use 404-vs-200 responses as a mild existence oracle. The real danger is the **pattern** — the day it's copied onto a function that returns or mutates data, it becomes a full breach.

Reference correct pattern already in the codebase: `sold-celebrate-calc` uses `verifyJwtAndScope()` and re-checks `lead.assigned_to_user_id === actorId`.

---

## Acceptance Criteria

- **AC-1** — Each of the 4 admin-invoked fns rejects any request whose bearer token does not **exactly** equal `SUPABASE_SERVICE_ROLE_KEY`, using a **timing-safe** comparison, returning `401` before any DB/service-role work. A request with a correct token still succeeds (regression).
- **AC-2** — Each of the 3 cron-invoked fns requires a shared secret (`CRON_SECRET` env, distinct from the service-role key) in a header and rejects (`401`) when it is missing/wrong, before any work.
- **AC-3** — The existing pg_cron jobs that invoke the 3 cron fns are updated **in the same change** to send the required secret, so scheduled notifications continue to fire. Verified end-to-end (a real overdue-followup / streak run still delivers).
- **AC-4** — The 4 admin server-action callers in `apps/admin` are confirmed to already send the service-role key as the bearer (they do today); no caller regression. If any does not, it is fixed in lockstep.
- **AC-5** — A negative test exists per function family: bad/absent token ⇒ `401`; correct token ⇒ normal behavior. Timing-safe compare is used (no early-return on length-only mismatch that leaks length — length check is allowed but the value compare must be constant-time).
- **AC-6** — Secrets set via Supabase secrets (not vault, not committed). `CRON_SECRET` documented in the deploy notes.
- **AC-7** — All 7 fns remain deployed `--no-verify-jwt` (do not flip to verify_jwt=true — the cron/admin-server callers have no user JWT). Auth is enforced *in-function* only.

---

## Implementation notes

**Shared helper (preferred):** add a small `_shared/serviceAuth.ts` with two guards so the pattern lives in one place:

```ts
import { timingSafeEqual } from 'https://deno.land/std/crypto/timing_safe_equal.ts';

function safeEq(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  return ea.length === eb.length && timingSafeEqual(ea, eb);
}

export function requireServiceRole(req: Request): Response | null {
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  return safeEq(token, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')
    ? null
    : new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
}

export function requireCronSecret(req: Request): Response | null {
  const got = req.headers.get('x-cron-secret') ?? '';
  return safeEq(got, Deno.env.get('CRON_SECRET') ?? '')
    ? null
    : new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
}
```

Each function calls the guard as its first line and returns the response if non-null.

**Cron job update (AC-3):** the pg_cron jobs (see `0026_followup_notification_cron.sql` and the streak/overdue schedules) invoke these fns via `net.http_post`. Add the `x-cron-secret` header there. This re-introduces a stored secret for cron — that's intended and supersedes the old "no secret needed" note in `nirman-crm/CLAUDE.md` (update that note). Store the secret read for the cron SQL the same way other cron secrets are handled; do **not** hardcode it in the migration file — pull from a settings row / vault as appropriate, or set it via `db query` post-deploy and document the step.

**Callers (AC-4):** the 4 admin fns are called from `apps/admin` server actions immediately after their RPC (e.g. after `post_developer_update`). Confirm each already forwards the service-role key as the bearer; they do per current code, so no change expected — just verify.

---

## Test / verification

- Unit/integration: each family — bad token ⇒ 401, correct token ⇒ 200 + expected side effect (mock FCM).
- End-to-end: after deploy, confirm a real scheduled run still delivers a notification (AC-3), and a `curl` with `Authorization: Bearer x` now returns 401 (was previously accepted).
- `flutter analyze` unaffected (no mobile change). Admin `tsc --noEmit` clean if any caller touched.

## Conventions (from `nirman-crm/CLAUDE.md`)

- No new migration needed unless the cron secret is stored via SQL — if so, it's the next numbered file after `0086`, applied via `supabase db push --linked`. **Never** MCP `apply_migration`.
- Redeploy each fn with `--no-verify-jwt` (unchanged).
- Update the CLAUDE.md push-notification note that currently says cron needs no secret — after this story, cron **does** carry `CRON_SECRET`.

## Dev Agent Record (Amelia, 2026-07-09)

**⚠️ Correct-course deviation from AC-1/AC-4 — the "all 4 admin fns forward the service-role
key" premise was wrong for 2 of them.** `send-assignment-notification` and
`send-bulk-assignment-notification` are invoked from the admin web app's **browser** client
(`assign-dialog.tsx`, `bulk-assign-dialog.tsx` — both `"use client"`, `@/lib/supabase/client`).
`supabase.functions.invoke` there sends the admin's **user JWT**, never the service-role key
(which must never reach a browser). A service-role bearer compare would 401 every real call and
is unsatisfiable from a browser. Fixed **correctly** instead:

- **assignment + bulk-assignment** → `verifyJwtAndScope()` + `role === 'admin'`, then all
  device-token queries scoped to the caller's `tenant_id` (closes the cross-tenant abuse vector
  the finding described). This matches the reference `sold-celebrate-calc` the story itself cites,
  and keeps `--no-verify-jwt` (AC-7 satisfied). **No caller change needed** (AC-4 outcome: verified,
  browser callers already send the right JWT).
- **developer-update + amendment** → `requireServiceRole()` (timing-safe service-role compare).
  Both have **no live caller yet** (backend-only / deferred deploy per migrations 0073, 0083;
  intended caller is a service-role context), so the service-role compare is correct and
  regression-free.
- **3 cron fns** → `requireCronSecret()` (`x-cron-secret` header vs `CRON_SECRET`).

**Files changed:**
- `supabase/functions/_shared/serviceAuth.ts` (new) — `safeEq` (hand-rolled constant-time,
  no external `deno.land/std` dependency), `requireServiceRole`, `requireCronSecret`; both guards
  reject when the expected secret is unset (misconfig ⇒ deny-all).
- 7 edge fns wired (imports + first-line guard; browser fns also tenant-scoped).
- `supabase/migrations/0087_cron_secret_auth.sql` (new) — re-schedules the 3 cron jobs to send
  `x-cron-secret` from vault `cron_secret` (streak-at-risk previously sent **no** auth header at all).
- `supabase/functions/_shared/serviceAuth.test.ts` (new) — 11 tests, all passing
  (`deno test --no-check --allow-env --allow-net`).
- `CLAUDE.md` push-notification note updated (cron now carries `CRON_SECRET`).

**AC status:** AC-1 met (mechanism split by real caller — see above), AC-2 ✓, AC-3 ✓ (migration
0087; end-to-end delivery still pending prod deploy + secret set), AC-4 ✓ (no regression; premise
corrected), AC-5 ✓ (tests pass), AC-6 — `CRON_SECRET` documented, secret-set is a deploy step,
AC-7 ✓ (all 7 remain `--no-verify-jwt`).

**Code review (3-lens adversarial, 2026-07-10):** Blind Hunter + Edge Case Hunter + inline
Acceptance Audit. **No auth-bypass, no timing oracle; tenant scoping and fail-closed behavior
verified correct.** One patch applied from the review:
- **Pinned `verify_jwt = false` for all 7 fns in `supabase/config.toml`** (new) — the whole
  in-function-auth model rests on the gateway staying off; a redeploy that forgot the
  `--no-verify-jwt` flag would flip the gateway to JWT-verify and silently 401 the cron/service
  callers *before* the in-fn guard runs. Codifying it makes AC-7 durable. Validated: config.toml
  parses, all 7 = false.

Deferred (pre-existing, not caused by this change — tracked, not fixed here):
- `process-overdue-followups` only re-scans `followup_overdue` events from the last 6 min; any
  edge-fn outage > ~6 min (incl. a future cron-secret misalignment) drops those pushes permanently
  because `mark_overdue_followups()` won't re-flag an already-flagged lead. Pre-existing window
  behavior; widening it risks the dedup logic — separate robustness task.
- `send-developer-update` / `send-amendment-notification` still have no live caller (backend-only,
  deferred deploy). `requireServiceRole` is correct for their intended service-role caller; wiring
  the caller is separate builder-ops work.

**Deploy steps (not yet run — needs prod):**
1. `openssl rand -hex 32` → `<SECRET>`
2. `supabase secrets set CRON_SECRET='<SECRET>'`
3. `supabase db query --linked "SELECT vault.create_secret('<SECRET>', 'cron_secret');"`
4. `supabase db push --linked` (applies 0087)
5. Redeploy all 7 fns `--no-verify-jwt`.
6. Verify: `curl -X POST .../process-overdue-followups` (no header) ⇒ 401; a real cron tick still delivers.

## Out of scope

- Full sweep of all ~60 `SECURITY DEFINER` DB functions for tenant scoping (sampled strong in the 2026-07-09 review; track as a separate audit task).
- Confirming no service-role key under a `NEXT_PUBLIC_*` var in Vercel (ops checklist item, not code).
- The `apps/admin` dev-points-at-prod footgun (separate operational fix).
