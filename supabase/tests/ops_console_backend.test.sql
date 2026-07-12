-- Story 9.2 (Epic 9) — Platform-admin ops backend. Structural + authority + behavioral guardrails.
-- Run via: supabase test db  (pgTAP), or:
--   docker exec -i supabase_db_supabase psql -U postgres -d postgres -f - < supabase/tests/ops_console_backend.test.sql
-- Proves: deny-all FORCE-RLS + audit immutability; every ops_* fn fail-closes on a non-platform
-- -admin caller (42501); the seeded platform admin can renew (delegating to the 9.1 seam,
-- writing BOTH a ledger row and an audit row), suspend, reactivate; cross-tenant reads work.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(32);

-- ── fixtures ────────────────────────────────────────────────────────────────────────────────
INSERT INTO public.plans (id, name, price_inr, interval_months, is_active)
VALUES ('00000000-0000-0000-0000-0000000000f1'::uuid, 'Ops Test Monthly', 1000, 1, true);
INSERT INTO public.tenants (id, name, status)
VALUES ('00000000-0000-0000-0000-00000000000a'::uuid, 'Ops Tenant A', 'active'),
       ('00000000-0000-0000-0000-00000000000b'::uuid, 'Ops Tenant B', 'active');
-- seed one platform admin (a1); (ee) is deliberately NOT an admin.
INSERT INTO public.platform_admins (user_id, note)
VALUES ('00000000-0000-0000-0000-0000000000a1'::uuid, 'test founder');

-- ── structural invariants ─────────────────────────────────────────────────────────────────
SELECT ok((SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.platform_admins'::regclass),
  'platform_admins has FORCE row-level security');                                              -- 1
SELECT ok((SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.ops_audit_log'::regclass),
  'ops_audit_log has FORCE row-level security');                                                -- 2
SELECT has_function('public','is_platform_admin', 'is_platform_admin() exists');               -- 3
SELECT ok(NOT has_function_privilege('anon','public.ops_renew_tenant(uuid,uuid,integer,text,text)','EXECUTE'),
  'anon cannot execute ops_renew_tenant');                                                      -- 4
SELECT ok(NOT has_function_privilege('anon','public.ops_list_tenants()','EXECUTE'),
  'anon cannot execute ops_list_tenants');                                                      -- 5
SELECT ok(NOT has_function_privilege('anon','public.ops_list_audit(integer,integer)','EXECUTE'),
  'anon cannot execute ops_list_audit');                                                        -- 6
SELECT ok(has_function_privilege('authenticated','public.ops_list_tenants()','EXECUTE'),
  'authenticated CAN execute ops_list_tenants (guard is the real check)');                      -- 7
SELECT ok(NOT has_table_privilege('authenticated','public.ops_audit_log','UPDATE'),
  'authenticated cannot UPDATE ops_audit_log (immutable)');                                     -- 8
SELECT ok(NOT has_table_privilege('authenticated','public.ops_audit_log','DELETE'),
  'authenticated cannot DELETE ops_audit_log (immutable)');                                     -- 9
SELECT ok(NOT has_table_privilege('authenticated','public.ops_audit_log','SELECT'),
  'authenticated cannot directly SELECT ops_audit_log (deny-all; read only via ops_list_audit)');
SELECT ok(NOT has_table_privilege('authenticated','public.platform_admins','SELECT'),
  'authenticated cannot directly SELECT platform_admins (admin allowlist never leaked)');
SELECT ok(
  (SELECT bool_and(proconfig IS NOT NULL) FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND prosecdef
     AND proname IN ('is_platform_admin','ops_renew_tenant','ops_suspend_tenant',
                     'ops_reactivate_tenant','ops_list_tenants','ops_list_tenant_payments','ops_list_audit')),
  'all new SECURITY DEFINER ops fns pin search_path');                                          -- 10

-- ── authority: a NON-platform-admin caller is denied on every ops fn ─────────────────────────
SELECT set_config('request.jwt.claims',
  json_build_object('sub','00000000-0000-0000-0000-0000000000ee','role','authenticated')::text, true);
SELECT throws_ok($$ SELECT public.ops_renew_tenant('00000000-0000-0000-0000-00000000000a'::uuid,
  '00000000-0000-0000-0000-0000000000f1'::uuid, 1000, 'upi', NULL) $$, '42501', NULL,
  'non-admin denied on ops_renew_tenant (42501)');                                              -- 11
SELECT throws_ok($$ SELECT public.ops_suspend_tenant('00000000-0000-0000-0000-00000000000a'::uuid) $$,
  '42501', NULL, 'non-admin denied on ops_suspend_tenant (42501)');                             -- 12
SELECT throws_ok($$ SELECT public.ops_reactivate_tenant('00000000-0000-0000-0000-00000000000a'::uuid) $$,
  '42501', NULL, 'non-admin denied on ops_reactivate_tenant (42501)');                          -- 13
SELECT throws_ok($$ SELECT * FROM public.ops_list_tenants() $$, '42501', NULL,
  'non-admin denied on ops_list_tenants (42501)');                                              -- 14
SELECT throws_ok($$ SELECT * FROM public.ops_list_tenant_payments('00000000-0000-0000-0000-00000000000a'::uuid) $$,
  '42501', NULL, 'non-admin denied on ops_list_tenant_payments (42501)');                       -- 15
SELECT throws_ok($$ SELECT * FROM public.ops_list_audit() $$, '42501', NULL,
  'non-admin denied on ops_list_audit (42501)');                                                -- 16

-- ── behavioral: seeded platform admin (a1) can drive the seam ────────────────────────────────
SELECT set_config('request.jwt.claims',
  json_build_object('sub','00000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
SELECT ok(public.is_platform_admin(), 'seeded platform admin passes is_platform_admin()');      -- 17

SELECT is(
  (public.ops_renew_tenant('00000000-0000-0000-0000-00000000000a'::uuid,
     '00000000-0000-0000-0000-0000000000f1'::uuid, 1000, 'upi', 'first ops renew') ->> 'status'),
  'active', 'ops_renew_tenant returns status active (delegates to renew_tenant)');              -- 18
SELECT is((SELECT count(*)::int FROM public.tenant_payments
             WHERE tenant_id='00000000-0000-0000-0000-00000000000a'::uuid), 1,
  'ops_renew_tenant delegated -> one tenant_payments ledger row');                              -- 19
SELECT is((SELECT count(*)::int FROM public.ops_audit_log
             WHERE action='renew_tenant'
               AND target_tenant_id='00000000-0000-0000-0000-00000000000a'::uuid), 1,
  'ops_renew_tenant wrote one audit row');                                                      -- 20

SELECT is(
  (public.ops_suspend_tenant('00000000-0000-0000-0000-00000000000a'::uuid, 'nonpayment') ->> 'status'),
  'suspended', 'ops_suspend_tenant returns suspended');                                         -- 21
SELECT is((SELECT status::text FROM public.tenants WHERE id='00000000-0000-0000-0000-00000000000a'::uuid),
  'suspended', 'tenant A is now suspended');                                                    -- 22
-- scoped to the fixture tenant: a developer's local DB may carry audit rows
-- from earlier manual e2e runs (unscoped count broke there, passed on fresh CI)
SELECT is((SELECT count(*)::int FROM public.ops_audit_log
             WHERE action='suspend_tenant'
               AND target_tenant_id='00000000-0000-0000-0000-00000000000a'::uuid), 1,
  'ops_suspend_tenant wrote one audit row');                                                    -- 23

SELECT is(
  (public.ops_reactivate_tenant('00000000-0000-0000-0000-00000000000a'::uuid, 'manual restore') ->> 'status'),
  'active', 'ops_reactivate_tenant returns active');                                            -- 24
SELECT is((SELECT status::text FROM public.tenants WHERE id='00000000-0000-0000-0000-00000000000a'::uuid),
  'active', 'tenant A is active again');                                                         -- 25
SELECT ok((SELECT paid_until FROM public.tenants WHERE id='00000000-0000-0000-0000-00000000000a'::uuid)
            > now() + interval '25 days',
  'reactivate did NOT touch paid_until (still ~1mo ahead from renew)');                          -- 26

-- ── cross-tenant reads ───────────────────────────────────────────────────────────────────────
SELECT cmp_ok((SELECT count(*)::int FROM public.ops_list_tenants()), '>=', 2,
  'ops_list_tenants returns ALL tenants (cross-tenant, >= 2)');                                  -- 27
SELECT is((SELECT count(*)::int FROM public.ops_list_tenant_payments('00000000-0000-0000-0000-00000000000a'::uuid)), 1,
  'ops_list_tenant_payments returns the tenant ledger row');                                     -- 28
SELECT is((SELECT action FROM public.ops_list_audit(10, 0) LIMIT 1), 'reactivate_tenant',
  'ops_list_audit returns newest first (last action = reactivate_tenant)');                      -- 29

-- ── tenant_not_found on a missing tenant ─────────────────────────────────────────────────────
SELECT throws_ok($$ SELECT public.ops_suspend_tenant('00000000-0000-0000-0000-0000000000cc'::uuid) $$,
  'P0002', NULL, 'ops_suspend_tenant on missing tenant raises tenant_not_found (P0002)');        -- 30

SELECT * FROM finish();
ROLLBACK;
