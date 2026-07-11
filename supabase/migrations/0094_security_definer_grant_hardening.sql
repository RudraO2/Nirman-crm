-- 0094_security_definer_grant_hardening.sql
-- SECURITY DEFINER sweep (Money Path #10) — least-privilege EXECUTE cleanup.
--
-- AUDIT RESULT (read-only prod catalog sweep, 2026-07-11): NO live vulnerability.
--   * search_path is pinned on EVERY public SECURITY DEFINER function
--     (either `public, extensions` or `''`) — no search-path-hijack vector.
--   * The 5 cron batch fns that intentionally process cross-tenant
--     (expire_lapsed_tenants, mark_overdue_followups, release_expired_holds,
--     streak_at_risk_targets, warn_expiring_holds) + set_current_tenant are
--     EXECUTE-locked to service_role only (anon=false, authenticated=false).
--   * create_lead_with_pii self-guards: it RAISEs missing_tenant_context /
--     missing_actor when auth_tenant_id()/auth.uid() are NULL, so an anon caller
--     dies immediately. The anon grant is dead weight, not a hole.
--   * auth_tenant_id keeps its anon grant on purpose (pure JWT helper used inside
--     RLS policies; returns NULL for anon — zero leak, revoking risks RLS eval).
--
-- This migration ONLY strips EXECUTE grants that are dead weight so the direct-
-- call surface matches least privilege. It is BEHAVIOUR-PRESERVING:
--   * create_lead_with_pii  — drop PUBLIC + anon; KEEP authenticated (the mobile
--     create-lead edge fn calls it under a user JWT — auth.uid() must be non-NULL).
--   * amendments_notify_logged / amendments_notify_status — trigger fns (RETURNS
--     trigger, not PostgREST-callable); drop PUBLIC + anon + authenticated.
--   * emit_inventory_changed / get_amendment_log_audience /
--     get_developer_update_audience — internal helpers invoked ONLY by other
--     SECURITY DEFINER fns, which run in the owner (postgres) context and so do
--     NOT consult the caller's grant; drop authenticated (PUBLIC/anon already absent).
--
-- postgres (owner) + service_role retain EXECUTE on all of the above, so every
-- app RPC and trigger path is unchanged. Prod head is 0093 (once pushed); this is
-- 0094. File-based, `supabase db push --linked`. NEVER MCP apply.

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'create_lead_with_pii',
        'amendments_notify_logged',
        'amendments_notify_status',
        'emit_inventory_changed',
        'get_amendment_log_audience',
        'get_developer_update_audience'
      )
  LOOP
    -- None of these may ever be reached by an unauthenticated / default-PUBLIC caller.
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);

    -- create_lead_with_pii is the ONE real authenticated RPC in this set — keep it.
    -- Everything else is a trigger fn or an internal-only helper: end users must
    -- not be able to call it directly, and its SECURITY DEFINER callers run as owner.
    IF r.proname <> 'create_lead_with_pii' THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', r.sig);
    END IF;
  END LOOP;
END $$;
