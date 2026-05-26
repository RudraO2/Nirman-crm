-- Story 1.1 (AC-4, AC-5, AC-7, AC-8) — tenant isolation contract test
--
-- After migration 0003, policies use JWT-only via auth_tenant_id():
--   CASE WHEN tenant_id ~ uuid_regex THEN tenant_id::uuid ELSE NULL END
-- GUC (app.current_tenant) branch removed; auth.jwt() reads from request.jwt.claims GUC.
--
-- Asserts:
--   1. anon role + no JWT claims            → 0 rows on users
--   2. anon role + no JWT claims            → 0 rows on tenants
--   3. authenticated + valid JWT tenant     → seed-tenant row visible
--   4. authenticated + valid JWT tenant     → correct tenant id returned
--   5. authenticated + nonexistent tenant   → 0 rows
--   6. authenticated + missing tenant claim → 0 rows
--   7. set_current_tenant RPC is service_role-only (authenticated denied EXECUTE)
--   8. service_role can execute set_current_tenant and GUC is bound
--
-- Run via: `supabase test db` (pgTAP runner). Requires pgtap extension.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(8);

-- Ensure seed tenant exists for the duration of the test
INSERT INTO public.tenants (id, name, timezone)
VALUES ('00000000-0000-0000-0000-000000000001'::uuid, 'Nirman Media (test)', 'Asia/Kolkata')
ON CONFLICT (id) DO NOTHING;

-- ────────────────────────────────────────────────────────────────────────────
-- 1 + 2: anon role, no JWT claims → 0 rows everywhere
-- ────────────────────────────────────────────────────────────────────────────
SET LOCAL ROLE anon;
SELECT is(
  (SELECT count(*)::int FROM public.users),
  0,
  'anon role with no tenant context sees 0 users'
);
SELECT is(
  (SELECT count(*)::int FROM public.tenants),
  0,
  'anon role with no tenant context sees 0 tenants'
);

-- ────────────────────────────────────────────────────────────────────────────
-- 3 + 4: authenticated + valid JWT tenant claim → seed tenant visible
-- auth.jwt() reads from request.jwt.claims GUC (set by PostgREST per-request)
-- ────────────────────────────────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000002","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"employee"}}',
  true);
SELECT is(
  (SELECT count(*)::int FROM public.tenants),
  1,
  'authenticated + valid JWT tenant claim sees exactly 1 tenant row'
);
SELECT is(
  (SELECT id FROM public.tenants LIMIT 1),
  '00000000-0000-0000-0000-000000000001'::uuid,
  'visible tenant row matches JWT claim'
);

-- ────────────────────────────────────────────────────────────────────────────
-- 5: authenticated + nonexistent tenant in JWT → 0 rows
-- ────────────────────────────────────────────────────────────────────────────
SELECT set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000002","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000099","role":"employee"}}',
  true);
SELECT is(
  (SELECT count(*)::int FROM public.tenants),
  0,
  'authenticated + nonexistent tenant JWT sees 0 tenants'
);

-- ────────────────────────────────────────────────────────────────────────────
-- 6: authenticated + missing tenant_id claim → 0 rows (auth_tenant_id() → NULL)
-- ────────────────────────────────────────────────────────────────────────────
SELECT set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000002","app_metadata":{"role":"employee"}}',
  true);
SELECT is(
  (SELECT count(*)::int FROM public.tenants),
  0,
  'authenticated + missing tenant_id claim sees 0 tenants'
);

-- ────────────────────────────────────────────────────────────────────────────
-- 7: authenticated role must NOT execute set_current_tenant (service_role only)
-- ────────────────────────────────────────────────────────────────────────────
SELECT throws_ok(
  $$ SELECT public.set_current_tenant('00000000-0000-0000-0000-000000000001'::uuid) $$,
  '42501',
  NULL,
  'authenticated role is denied EXECUTE on set_current_tenant'
);

-- ────────────────────────────────────────────────────────────────────────────
-- 8: service_role CAN execute set_current_tenant and GUC is bound
-- ────────────────────────────────────────────────────────────────────────────
SET LOCAL ROLE service_role;
SELECT public.set_current_tenant('00000000-0000-0000-0000-000000000001'::uuid);
SELECT is(
  current_setting('app.current_tenant', true),
  '00000000-0000-0000-0000-000000000001',
  'service_role can execute set_current_tenant and GUC is bound'
);

SELECT * FROM finish();

ROLLBACK;
