-- 0079_booking_dashboard.sql
-- Story 15.5 (Epic 15) — FR-55. Booking dashboard read RPCs.
--
-- get_active_holds(project?, agent?) — active holds (released_at IS NULL) scoped to the caller's
--   visible_user_ids() (12.5): builder_head → all internal; team_leader → subtree; rep → self.
--   Returns unit/lead/agent + seconds_to_expiry for the client countdown. Lead name decrypted (vault).
-- get_booking_stats(period_days, project?) — confirmed bookings + hold→sold conversion % over the
--   period, same scope. Both SECURITY DEFINER (own tenant + scope enforced explicitly).
--
-- File-based migration; never MCP apply.

BEGIN;

-- 1. get_active_holds -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_active_holds(
  p_project_id uuid DEFAULT NULL,
  p_agent_id   uuid DEFAULT NULL
)
RETURNS TABLE (
  hold_id           uuid,
  unit_id           uuid,
  unit_no           text,
  project_id        uuid,
  lead_id           uuid,
  lead_name         text,
  holding_agent_id  uuid,
  agent_name        text,
  held_at           timestamptz,
  expires_at        timestamptz,
  seconds_to_expiry bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
  v_tenant_id uuid;
  v_pii_key   text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  SELECT decrypted_secret INTO v_pii_key FROM vault.decrypted_secrets WHERE name = 'lead_pii_key' LIMIT 1;

  RETURN QUERY
  SELECT
    h.id, h.unit_id, u.unit_no, u.project_id, h.lead_id,
    CASE WHEN v_pii_key IS NOT NULL AND l.name_encrypted IS NOT NULL
         THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key) ELSE NULL END,
    h.holding_agent_id, ag.email_or_username,
    h.held_at, h.expires_at,
    GREATEST(0, EXTRACT(EPOCH FROM (h.expires_at - now()))::bigint)
  FROM public.unit_holds h
  JOIN public.units u ON u.id = h.unit_id
  LEFT JOIN public.leads l ON l.id = h.lead_id
  LEFT JOIN public.users ag ON ag.id = h.holding_agent_id
  WHERE h.tenant_id = v_tenant_id
    AND h.released_at IS NULL
    AND h.holding_agent_id IN (SELECT v.user_id FROM public.visible_user_ids() v)
    AND (p_project_id IS NULL OR u.project_id = p_project_id)
    AND (p_agent_id   IS NULL OR h.holding_agent_id = p_agent_id)
  ORDER BY h.expires_at ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_active_holds(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_active_holds(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.get_active_holds(uuid, uuid) IS
  'Story 15.5 — active holds (released_at IS NULL) scoped to visible_user_ids(); unit/lead/agent + seconds_to_expiry. Lead name decrypted via vault. Filter by project/agent.';

-- 2. get_booking_stats ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_booking_stats(
  p_period_days int  DEFAULT 30,
  p_project_id  uuid DEFAULT NULL
)
RETURNS TABLE (
  confirmed_bookings int,
  active_holds       int,
  total_holds        int,
  conversion_pct     numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  RETURN QUERY
  WITH scoped AS (
    SELECT h.outcome, h.released_at
    FROM public.unit_holds h
    JOIN public.units u ON u.id = h.unit_id
    WHERE h.tenant_id = v_tenant_id
      AND h.holding_agent_id IN (SELECT v.user_id FROM public.visible_user_ids() v)
      AND (p_project_id IS NULL OR u.project_id = p_project_id)
      AND (p_period_days IS NULL OR h.held_at >= now() - make_interval(days => p_period_days))
  )
  SELECT
    COUNT(*) FILTER (WHERE outcome = 'converted')::int,
    COUNT(*) FILTER (WHERE released_at IS NULL)::int,
    COUNT(*)::int,
    ROUND(COUNT(*) FILTER (WHERE outcome = 'converted')::numeric * 100.0 / NULLIF(COUNT(*), 0), 1)
  FROM scoped;
END;
$$;

REVOKE ALL ON FUNCTION public.get_booking_stats(int, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_booking_stats(int, uuid) TO authenticated;

COMMENT ON FUNCTION public.get_booking_stats(int, uuid) IS
  'Story 15.5 — confirmed bookings + active holds + hold->sold conversion % over period, scoped to visible_user_ids(). Filter by project.';

COMMIT;
