-- Builder-ops (Epics 12-16) structural + privilege invariants — durable regression guardrails.
-- Run via: supabase test db  (pgTAP). These assert the security/shape guarantees that behavioral
-- review proved, so a future migration can't silently regress them (drop FORCE RLS, re-grant anon,
-- break an enum, weaken append-only, drop a unique index).

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(15);

-- 1. every new table has FORCE row-level security
SELECT ok(
  (SELECT bool_and(relrowsecurity AND relforcerowsecurity)
   FROM pg_class
   WHERE relnamespace = 'public'::regnamespace AND relkind = 'r'
     AND relname IN ('agencies','agency_projects','towers','units','developer_updates',
                     'unit_holds','amendments','amendment_events','tenant_execution_team')),
  'all 9 new builder-ops tables have FORCE row-level security'
);

-- 2-5. enums carry exactly their expected labels
SELECT set_eq(
  $$SELECT e.enumlabel::text FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='unit_status'$$,
  ARRAY['available','hold','sold','blocked'], 'unit_status enum labels');
SELECT set_eq(
  $$SELECT e.enumlabel::text FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='role_tier'$$,
  ARRAY['super_admin','builder_head','team_leader','front_line_rep','partner_agency','receptionist'], 'role_tier enum labels');
SELECT set_eq(
  $$SELECT e.enumlabel::text FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='hold_outcome'$$,
  ARRAY['converted','released','expired','cancelled'], 'hold_outcome enum labels');
SELECT set_eq(
  $$SELECT e.enumlabel::text FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='amendment_status'$$,
  ARRAY['requested','acknowledged','in_progress','done','rejected'], 'amendment_status enum labels');

-- 6. the single-active-hold partial unique index exists (the anti-double-book invariant)
SELECT ok(
  EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='unit_holds_one_active_idx'),
  'unit_holds single-active partial-unique index present');

-- 7-8. amendment_events is append-only for app roles (no UPDATE/DELETE privilege)
SELECT ok(NOT has_table_privilege('authenticated','public.amendment_events','UPDATE'),
  'authenticated cannot UPDATE amendment_events (append-only)');
SELECT ok(NOT has_table_privilege('authenticated','public.amendment_events','DELETE'),
  'authenticated cannot DELETE amendment_events (append-only)');

-- 9-13. anon can never execute the sensitive builder-ops RPCs
SELECT ok(NOT has_function_privilege('anon','public.hold_unit(uuid,uuid)','EXECUTE'),                'anon cannot execute hold_unit');
SELECT ok(NOT has_function_privilege('anon','public.confirm_booking(uuid,boolean)','EXECUTE'),       'anon cannot execute confirm_booking');
-- signature grew in 0085 (flexible unit numbering); resolve it dynamically so a
-- future param change can't abort this whole file again (unknown signature = error)
SELECT ok(
  (SELECT bool_and(NOT has_function_privilege('anon', p.oid, 'EXECUTE'))
   FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace AND p.proname='generate_unit_grid'),
  'anon cannot execute generate_unit_grid');
SELECT ok(NOT has_function_privilege('anon','public.get_project_units(uuid)','EXECUTE'),             'anon cannot execute get_project_units');
SELECT ok(NOT has_function_privilege('anon','public.set_amendment_status(uuid,public.amendment_status)','EXECUTE'), 'anon cannot execute set_amendment_status');

-- 14. release_expired_holds is service-role only (system fn, not callable by app users)
SELECT ok(NOT has_function_privilege('authenticated','public.release_expired_holds()','EXECUTE'),
  'authenticated cannot execute release_expired_holds (system fn)');

-- 15. every new SECURITY DEFINER fn pins search_path (no mutable-search-path hijack)
SELECT ok(
  (SELECT bool_and(p.proconfig IS NOT NULL)
   FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace AND p.prosecdef
     AND p.proname IN ('hold_unit','confirm_booking','generate_unit_grid','get_project_units',
       'change_unit_inventory_state','release_expired_holds','log_amendment','set_amendment_status',
       'post_developer_update','set_user_hierarchy','verify_visit')),
  'all new SECURITY DEFINER fns pin search_path');

SELECT * FROM finish();
ROLLBACK;
