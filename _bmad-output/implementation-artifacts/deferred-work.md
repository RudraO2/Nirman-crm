# Deferred Work

## Deferred from: code review of stories 7-1, 7-2, 7-3, 7-4, 2-8 (2026-05-28)

- **Read RPCs missing tenant gate** (D1, all motivation/archive RPCs) — 0030/0031/0034/0035 filter only by `assigned_to_user_id = auth.uid()`, not `tenant_id = auth_tenant_id()`. Safe under single-tenant V1 (`users.id` globally unique); tighten when multi-tenant lands so the pattern matches `restore_lead`.
- **`streak-at-risk` edge fn publicly invokable** (D2, 7.3) — `verify_jwt=false` lets anyone POST and trigger an FCM+RPC pass. All Nirman cron-driven edge fns share this pattern per CLAUDE.md; addressing requires a shared-secret header at the gateway across all cron fns — broader security-hardening epic.
- **`device_tokens` not joined by tenant on streak push** (D3, 7.3) — current single-tenant deployment makes this moot; add `dt.tenant_id = s.tenant_id` join condition when device-token rows can span tenants.
- **7.1 AC-1 label drift** (D4) — UI splits the spec's "Sold this month: N" / "Follow-up streak: N days" / "Conversion rate: X.X%" into value-on-top + small-label-below tiles. Functionally equivalent; product call.
- **2.8 AC-3 colored status badge** (D5) — already marked `[~]` deferred in 2.8; LeadCard renders status text but not the spec'd Dead-red / Sold-green / Future-amber chip. UI polish.
- **2.8 AC-9 50k-archive load test** (D6) — RPC verified on empty + 1 row; no 50k load test infra in repo.
- **7.4 monthly best ties don't celebrate** (D7) — `isNewBest` is strict `>`. Spec says "beats", so this matches; flagged in case product wants tie-celebration.
- **7.2 `days_to_close = 0` cosmetic** (D8) — same-day close reads "0 days to close" on the earned-moment card. Polish.
- **Error swallowing in motivation/archive repository helpers** (D9, all) — `catch (_)` returns defaults; useful for UX but obscures auth/RLS denials. Add `debugPrint` or crash reporter integration in a logging-hardening pass.
- **Orphan archived leads sort last** (D10, 2.8) — leads with `status IN (dead,sold,future)` but no `status_changed` event get `archived_at = NULL` and sort to bottom. Affects legacy data only; backfill once if it becomes user-visible.

## Epic 3 close-out + branch reconciliation (2026-05-28)

- **Diverged histories merged into main.** `origin/main` carried Epic 1.5–1.8;
  feature branch carried Epic 2 + 3. Both forked at story 1.4 and were
  rebased/recreated, so 16 add/add conflicts. Hand-resolved to the superset
  (kept device-tested `setSession` login, shared `auth_validators`, cold-start
  router notifier, real HomeScreen + Epic 2/3 routes, Firebase/notifications
  init, custom theme). `flutter analyze`: 0 errors. main is now source of truth;
  GitHub default branch switched to main.
- **8 stale branches NOT deleted** (1.1–1.3, 1.5–1.8). Their content is in main
  but via rebased/recreated commits, so git reports them un-merged. Deleting is
  unprovable data-loss — left for manual review. The 3 provably-merged branches
  (1.4, 2.1, 2.2) were deleted.

### Epic 3.5 push notifications — CONFIGURED + VERIFIED end-to-end
- ✅ `FCM_SERVICE_ACCOUNT` edge secret set from Firebase admin JSON (project crm-lms-57c5d).
- ✅ Both cron jobs scheduled + active (`send-followup-notifications` every min,
  `process-overdue-followups` every 5 min). They were never scheduled before
  (pg_cron wasn't enabled when 0026 ran; re-scheduled 2026-05-28).
- ✅ Live test: set a lead's `next_followup_at` to now, invoked fn → `{"sent":1}`
  (FCM accepted the registered device token; dedup event logged). Lead restored.
- **vault `service_role_key` NO LONGER NEEDED** — both notification fns have
  `verify_jwt=false`, so the cron's gateway call succeeds with empty/missing
  bearer (verified 200 with no auth). The 0026 prerequisite note is obsolete.
  `SUPABASE_SERVICE_ROLE_KEY` env (used internally by the fns) is platform-injected.
- Remaining: only visual confirmation of the push on the physical device, and
  ongoing real-world cron firing (jobs are live).

## Deferred from: code review of 1-3-admin-creates-employee-accounts round 2 (2026-05-27)

- **AC-7 unstable error string matching** — `authErr?.message` substring checks for GoTrue duplicate detection are fragile across GoTrue upgrades. Pre-existing; not introduced by review patches.
- **Orphaned auth user no alerting** — deleteUser failure leaves auth.users orphan with no dead-letter/alert path. Pre-existing.
- **Team page no retry mechanism** — error state renders static text with no reload link. UX improvement; future story.
- **No copy-to-clipboard button on password modal** — `select-all` CSS fails on iOS Safari. UX improvement; future story.
- **Username lowercasing not echoed in response** — success response returns only `user_id`; stored normalised name not confirmed to caller. UX; future story.
- **Unicode normalisation divergence (JS vs Postgres lower())** — Turkish dotless-i and similar cause JS/PG `lower()` to diverge. Pending D2 decision; if ASCII restriction chosen, becomes a patch.
- **REVOKE INSERT comment misleading** — comment says "employees blocked" but service_role is the only insert path; both admins and employees are blocked via client JWT. Comment-only fix; future migration.

## Deferred from: code review of 1-2-bootstrap-initial-admin-account (2026-05-26)

- **Dual password storage credential sync** — `public.users.bcrypt_password_hash` and `auth.users` both store credentials. Story 1.4/1.5 must enforce sync on password change. Documented as intentional in Dev Notes.
- **validatePasswordStrength redundant with Zod** — min(8) enforced twice; cosmetic inconsistency, no behavior impact.
- **Race condition concurrent bootstrap calls** — two simultaneous calls can both pass idempotency check. Recommend `UNIQUE INDEX on public.users (tenant_id) WHERE role='admin'`. Low probability for one-time endpoint.
- **_shared/errors.ts duplication** — `bootstrap-admin/_shared/errors.ts` is a local copy due to MCP bundler limitation. Must stay in sync with canonical `functions/_shared/errors.ts`. Resolve when switching to Supabase CLI deploy.
- **Content-Type not validated** — `req.json()` parses any JSON regardless of Content-Type. Low risk for server-to-server endpoint.
- **No rate limiting** — bootstrap endpoint has no per-IP throttle or invocation counter. Acceptable for one-time bootstrap; disable after use.
- **No max body size** — large bodies buffered before Zod rejects. Low risk given Edge Function memory limits.
- **SEED_TENANT_ID existence not pre-checked** — FK violation if seed tenant missing. Documented dependency: seed.sql must run before bootstrap.
- **app_metadata role vs users.role drift** — both written at bootstrap; if one updated independently they diverge. Story 1.4/1.5 must treat one as canonical (recommend `auth.users.app_metadata` as JWT source of truth).
- **must_change_password=false** — spec AC-1 requires false for bootstrap admin. Story 1.5 may revisit for security hardening.

## Deferred from: code review of 1-3-admin-creates-employee-accounts (2026-05-27)

- **Race condition concurrent duplicate creation** — Two simultaneous admin requests for the same username can both pass auth.createUser before either errors. DB unique constraints handle worst case; full serialization is future work.
- **Password irrecoverably lost if tab closes** — Window between HTTP response arriving and React state committing. Inherent to plaintext-once design; admin reset path available in story 1.5.
- **actor_id FK relies on story 1.2 UUID alignment** — user_events.actor_id FK references public.users(id); actor UUID comes from auth.users. Story 1.2 bootstrap guarantees matching UUIDs; best-effort insert absorbs failure silently.
- **No per-tenant employee count limit** — Any admin can create unlimited employees with no seat/quota check. Product decision; future story.
- **Middleware no 403 redirect for authenticated employees** — Authenticated employees hitting /team are redirected to /login instead of a forbidden page; confusing UX loop. UX improvement; future story.
- **Username lowercase display mismatch** — Admin types `Alice`, Edge Function stores `alice`, UI shows stored value only after router.refresh(). Cosmetic; future story.
- **No CSP/X-Frame-Options headers** — Middleware sets no security headers; admin pages could be clickjacked. Security hardening epic; separate story.
- **No CSRF protection on Edge Function** — Any authenticated same-browser page could call create-employee. Supabase CORS provides primary protection; deeper CSRF hardening deferred.
- **Tenant DB existence not validated** — Admin's JWT tenant_id claim is trusted without verifying the tenant row still exists in public.tenants. JWT validity is sufficient guard; explicit DB check deferred.

## Deferred from: code review of 1-1-initialize-multi-tenant-schema-with-rls (2026-05-26)

- 0001→0002 deployment window: security gap exists between the two migration files being applied sequentially. Any user who authenticates after 0001 but before 0002 lands operates under permissive old policies and can call `set_current_tenant` as authenticated. Mitigate via atomic deployment practice (disable external access / Supabase pause during migration run) — not a code-level fix.
