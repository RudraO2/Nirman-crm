# Deferred Work

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
