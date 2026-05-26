-- Story 1.1 (AC-4, AC-5, AC-7, AC-8) — tenant isolation contract test
--
-- After migration 0002, policies use:
--   COALESCE(NULLIF(current_setting('app.current_tenant', true), '')::uuid,
--            ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid)
--
-- Asserts:
--   1. anon role with no JWT + no GUC          → 0 rows
--   2. authenticated + GUC set to seed         → seed-tenant rows only
--   3. authenticated + GUC set to nonexistent  → 0 rows
--   4. authenticated + empty GUC + no JWT      → 0 rows
--   5. set_current_tenant RPC is service_role-only (authenticated must be denied EXECUTE)
--
-- Run via: `supabase test db` (pgTAP-based runner). Requires pgtap extension.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(8);

-- Ensure seed tenant exists for the duration of the test
INSERT INTO public.tenants (id, name, timezone)
VALUES ('00000000-0000-0000-0000-000000000001'::uuid, 'Nirman Media (test)', 'Asia/Kolkata')
ON CONFLICT (id) DO NOTHING;

-- ────────────────────────────────────────────────────────────────────────────
-- 1 + 2: anon role, no JWT, no GUC → 0 rows everywhere
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
-- 3 + 4: authenticated + seed-tenant GUC → seed tenant visible
-- ────────────────────────────────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SELECT set_config('app.current_tenant', '00000000-0000-0000-0000-000000000001', true);
SELECT is(
  (SELECT count(*)::int FROM public.tenants),
  1,
  'authenticated + seed GUC sees exactly 1 tenant row'
);
SELECT is(
  (SELECT id FROM public.tenants LIMIT 1),
  '00000000-0000-0000-0000-000000000001'::uuid,
  'visible tenant row is the seed tenant'
);

-- ────────────────────────────────────────────────────────────────────────────
-- 5: authenticated + nonexistent-tenant GUC → 0 rows
-- ────────────────────────────────────────────────────────────────────────────
SELECT set_config('app.current_tenant', '00000000-0000-0000-0000-000000000099', true);
SELECT is(
  (SELECT count(*)::int FROM public.tenants),
  0,
  'authenticated + nonexistent GUC sees 0 tenants'
);

-- ────────────────────────────────────────────────────────────────────────────
-- 6: authenticated + empty GUC + no JWT → 0 rows (COALESCE-both-NULL path)
-- ────────────────────────────────────────────────────────────────────────────
SELECT set_config('app.current_tenant', '', true);
SELECT is(
  (SELECT count(*)::int FROM public.tenants),
  0,
  'authenticated + empty GUC + no JWT sees 0 tenants'
);

-- ────────────────────────────────────────────────────────────────────────────
-- 7: authenticated role must NOT be able to execute set_current_tenant
--    (post-0002 lockdown — service_role only)
-- ────────────────────────────────────────────────────────────────────────────
SELECT throws_ok(
  $$ SELECT public.set_current_tenant('00000000-0000-0000-0000-000000000001'::uuid) $$,
  '42501',  -- insufficient_privilege
  NULL,
  'authenticated role is denied EXECUTE on set_current_tenant'
);

-- ────────────────────────────────────────────────────────────────────────────
-- 8: service_role CAN execute set_current_tenant and bind the GUC
-- ────────────────────────────────────────────────────────────────────────────
SET LOCAL ROLE service_role;
SELECT public.set_current_tenant('00000000-0000-0000-0000-000000000001'::uuid);
-- service_role bypasses RLS, but the GUC should still be set:
SELECT is(
  current_setting('app.current_tenant', true),
  '00000000-0000-0000-0000-000000000001',
  'service_role can execute set_current_tenant and the GUC is bound'
);

SELECT * FROM finish();

ROLLBACK;
