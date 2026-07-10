-- 0090_ops_list_plans.sql
-- Story 9.4 (Epic 9) — ops console web UI dependency.
--
-- DISCOVERED GAP: the ops console renew form must pick a plan_id for
-- ops_renew_tenant(p_tenant_id, p_plan_id, ...), but 0088 made `plans` deny-all
-- RLS (no client SELECT) and 0089's ops_list_tenants() returns only plan_NAME,
-- not plan_id. There was no guarded way to enumerate the plan catalogue. This
-- migration adds the single missing read — a platform-admin-guarded
-- ops_list_plans() — mirroring the 0089 ops_list_* pattern exactly.
--
-- Additive only. Does NOT touch 0088/0089 objects or grants. Same architecture:
-- RLS-native, platform-admin JWT + is_platform_admin() guard, no service-role.
--
-- Prod head is 0089. This is 0090. Run `supabase migration list` before adding.
-- File-based migration, applied via `supabase db push --linked`. NEVER MCP apply.
-- (Story 9.4 is FREE/LOCAL — this is applied to the local Docker stack only and
--  NOT pushed to prod yet; deploy alongside the ops console rollout.)

BEGIN;

CREATE OR REPLACE FUNCTION public.ops_list_plans()
RETURNS TABLE (
  id              uuid,
  name            text,
  price_inr       integer,
  interval_months integer,
  is_active       boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT p.id, p.name, p.price_inr, p.interval_months, p.is_active
      FROM public.plans p
     WHERE p.is_active
     ORDER BY p.interval_months ASC, p.price_inr ASC, p.name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.ops_list_plans() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_list_plans() TO authenticated;

COMMENT ON FUNCTION public.ops_list_plans() IS
  'Story 9.4 — platform-admin-guarded read of the ACTIVE plan catalogue for the ops console renew form (id + interval + price). The plans table is otherwise deny-all RLS (0088). Ordered by interval then price. Additive to 0089; same RLS-native guard.';

COMMIT;
