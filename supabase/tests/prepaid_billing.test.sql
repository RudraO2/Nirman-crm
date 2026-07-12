-- Story 9.1 (Epic 9) — prepaid access-gating seam. Structural + behavioral guardrails.
-- Run via: supabase test db  (pgTAP). Proves the security shape AND the two traps that
-- review must never let regress: (a) expire skips paid_until IS NULL tenants, (b)
-- get_my_billing_status stays readable while the tenant is suspended.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(22);

-- ── fixtures ────────────────────────────────────────────────────────────────────────────────
INSERT INTO public.plans (id, name, price_inr, interval_months, is_active)
VALUES ('00000000-0000-0000-0000-0000000000f1'::uuid, 'Test Monthly', 1000, 1, true);
INSERT INTO public.tenants (id, name, status)
VALUES ('00000000-0000-0000-0000-00000000000a'::uuid, 'Tenant A', 'active'),
       ('00000000-0000-0000-0000-00000000000b'::uuid, 'Tenant B', 'active');

-- ── structural invariants ─────────────────────────────────────────────────────────────────
SELECT ok((SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.plans'::regclass),
  'plans has FORCE row-level security');
SELECT ok((SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.tenant_payments'::regclass),
  'tenant_payments has FORCE row-level security');
SELECT has_column('public','tenants','paid_until', 'tenants.paid_until column exists');
SELECT has_column('public','tenants','plan_id',    'tenants.plan_id column exists');

SELECT ok(NOT has_function_privilege('anon','public.renew_tenant(uuid,uuid,integer,text,text)','EXECUTE'),
  'anon cannot execute renew_tenant');
SELECT ok(NOT has_function_privilege('authenticated','public.renew_tenant(uuid,uuid,integer,text,text)','EXECUTE'),
  'authenticated cannot execute renew_tenant (service-role seam)');
SELECT ok(NOT has_function_privilege('authenticated','public.expire_lapsed_tenants()','EXECUTE'),
  'authenticated cannot execute expire_lapsed_tenants (system fn)');
SELECT ok(NOT has_function_privilege('anon','public.get_my_billing_status()','EXECUTE'),
  'anon cannot execute get_my_billing_status');
SELECT ok(has_function_privilege('authenticated','public.get_my_billing_status()','EXECUTE'),
  'authenticated CAN execute get_my_billing_status');
SELECT ok(
  (SELECT bool_and(proconfig IS NOT NULL) FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND prosecdef
     AND proname IN ('renew_tenant','expire_lapsed_tenants','get_my_billing_status')),
  'all new SECURITY DEFINER fns pin search_path');

-- ── behavioral: renew ───────────────────────────────────────────────────────────────────────
SELECT is(
  (public.renew_tenant('00000000-0000-0000-0000-00000000000a'::uuid,
                        '00000000-0000-0000-0000-0000000000f1'::uuid, 1000, 'upi', 'first') ->> 'status'),
  'active', 'renew_tenant returns status active');
SELECT ok((SELECT paid_until FROM public.tenants WHERE id='00000000-0000-0000-0000-00000000000a'::uuid)
            > now() + interval '25 days',
  'renew extends paid_until ~1 month ahead');
SELECT is((SELECT count(*)::int FROM public.tenant_payments
             WHERE tenant_id='00000000-0000-0000-0000-00000000000a'::uuid), 1,
  'renew inserts one ledger row');

-- stacking: a second renew BEFORE expiry extends from paid_until, not now().
-- Amount differs from the first (2000 vs 1000) so the 0102 idempotency window
-- (identical tenant/plan/amount/method/operator within 60s = same physical
-- collection) does not dedupe this legitimately distinct payment.
SELECT public.renew_tenant('00000000-0000-0000-0000-00000000000a'::uuid,
                           '00000000-0000-0000-0000-0000000000f1'::uuid, 2000, 'upi', 'second');
SELECT ok((SELECT paid_until FROM public.tenants WHERE id='00000000-0000-0000-0000-00000000000a'::uuid)
            > now() + interval '50 days',
  'second renew stacks from paid_until (not now)');

-- 0102 idempotency: an IDENTICAL repeat within 60s is a double-click, not a
-- new collection — returns deduplicated:true and writes NO third ledger row.
SELECT is(
  (public.renew_tenant('00000000-0000-0000-0000-00000000000a'::uuid,
                        '00000000-0000-0000-0000-0000000000f1'::uuid, 2000, 'upi', 'second') ->> 'deduplicated'),
  'true', '0102: identical repeat renew within 60s is deduplicated');
SELECT is((SELECT count(*)::int FROM public.tenant_payments
             WHERE tenant_id='00000000-0000-0000-0000-00000000000a'::uuid), 2,
  '0102: dedupe leaves the ledger at two rows (no double-charge)');

-- ── behavioral: expiry ────────────────────────────────────────────────────────────────────
-- A: lapsed active -> must be suspended.  B: active with paid_until NULL -> must be untouched.
UPDATE public.tenants SET paid_until = now() - interval '1 day', status = 'active'
 WHERE id='00000000-0000-0000-0000-00000000000a'::uuid;
SELECT ok(public.expire_lapsed_tenants() >= 1, 'expire_lapsed_tenants suspends >=1 lapsed tenant');
SELECT is((SELECT status::text FROM public.tenants WHERE id='00000000-0000-0000-0000-00000000000a'::uuid),
  'suspended', 'lapsed active tenant is now suspended');
SELECT is((SELECT status::text FROM public.tenants WHERE id='00000000-0000-0000-0000-00000000000b'::uuid),
  'active', 'tenant with paid_until NULL is NEVER auto-suspended');

-- ── behavioral: get_my_billing_status ────────────────────────────────────────────────────
-- admin of the now-SUSPENDED tenant A must still get a reading (the recharge-screen case)
SELECT set_config('request.jwt.claims',
  json_build_object('app_metadata',
    json_build_object('role','admin','tenant_id','00000000-0000-0000-0000-00000000000a'))::text, true);
SELECT is((public.get_my_billing_status() ->> 'status'), 'suspended',
  'get_my_billing_status readable while tenant suspended (bypasses auth_tenant_id)');

-- employee caller: 0092 (Story 9.6) deliberately relaxed this from admin-only —
-- ANY tenant member may read billing status so the app can show the recharge
-- screen + advance-expiry warning instead of a raw error.
SELECT set_config('request.jwt.claims',
  json_build_object('app_metadata',
    json_build_object('role','employee','tenant_id','00000000-0000-0000-0000-00000000000a'))::text, true);
SELECT is((public.get_my_billing_status() ->> 'status'), 'suspended',
  'employee can read own-tenant billing status (0092: lockout screen)');

-- admin whose JWT tenant_id points at no existing tenant row -> raises (not null-status)
SELECT set_config('request.jwt.claims',
  json_build_object('app_metadata',
    json_build_object('role','admin','tenant_id','00000000-0000-0000-0000-0000000000cc'))::text, true);
SELECT throws_ok($$ SELECT public.get_my_billing_status() $$, '42501',
  NULL, 'admin with missing-tenant JWT denied (tenant_missing 42501)');

SELECT * FROM finish();
ROLLBACK;
