-- 0095_get_my_projects.sql
-- get_my_projects() — closes the Story 14.3-mobile deferred item (partner
-- project-picker over-lists, deferred-work.md §"14-3-mobile-availability-grid").
--
-- The mobile project picker read projects directly (leads.fetchProjects →
-- .from('projects'), tenant-scoped only), so a partner_agency user saw the
-- *names* of projects NOT shared to their agency (the grid RPC still denied the
-- units — no data leak, but a scope/UX wart, and unfixable client-side because
-- role_tier may be absent from the JWT / 12.3 backfill not run). This RPC scopes
-- the list server-side the same way get_project_units (0072) scopes units:
--   partner_agency → only agency-shared projects (via agency_projects)
--   every other tier → all active tenant projects (identical to the prior direct
--                      read — ZERO behaviour change for internal users)
--
-- Return shape (id, name) matches the mobile ProjectRef exactly, so
-- lead_repository.fetchProjects() is a drop-in swap. Active-only, name-ordered
-- (same as the prior read). SECURITY DEFINER, search_path-pinned, authenticated-
-- only (0094 least-privilege posture), inherits the 0056 tenant chokepoint via
-- auth_tenant_id().
--
-- NOTE: the sibling deferred item "hold lead-picker is caller-own-leads only"
-- (deferred-work.md §"15-2-mobile-hold-unit") needs NO new backend — the
-- team-scoped read get_team_leads already exists on prod (migration 0060) and is
-- scoped by visible_user_ids(); that item is a pure mobile-wiring change.
--
-- Prod head is expected to be 0094 once Money-Path #3 is pushed; this is 0095.
-- File-based, `supabase db push --linked`. NEVER MCP apply.

CREATE OR REPLACE FUNCTION public.get_my_projects()
RETURNS TABLE(id uuid, name text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_tenant_id uuid;
  v_tier      public.role_tier;
  v_agency_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  v_tenant_id := public.auth_tenant_id();
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'missing_tenant_context' USING ERRCODE = 'P0001';
  END IF;

  v_tier := public.auth_role_tier();

  IF v_tier = 'partner_agency' THEN
    -- partner sandbox: only projects shared to the caller's agency (mirrors the
    -- get_project_units agency gate). NULL agency ⇒ empty set (fail-closed).
    SELECT u.agency_id INTO v_agency_id FROM public.users u WHERE u.id = auth.uid();

    RETURN QUERY
    SELECT p.id, p.name
    FROM public.projects p
    JOIN public.agency_projects ap
      ON ap.project_id = p.id
     AND ap.tenant_id  = p.tenant_id
     AND ap.agency_id  = v_agency_id
    WHERE p.tenant_id = v_tenant_id
      AND p.is_active = true
    ORDER BY p.name;
  ELSE
    -- all internal tiers: every active tenant project (identical to the prior
    -- direct .from('projects') read — no behaviour change).
    RETURN QUERY
    SELECT p.id, p.name
    FROM public.projects p
    WHERE p.tenant_id = v_tenant_id
      AND p.is_active = true
    ORDER BY p.name;
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_projects() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_projects() TO authenticated;
