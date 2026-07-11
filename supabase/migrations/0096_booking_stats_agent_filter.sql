-- 0096_booking_stats_agent_filter.sql
-- Story 15.5-mobile follow-up — add an optional p_agent_id to get_booking_stats so
-- the booking-dashboard stat tiles can be narrowed to a single agent, matching the
-- agent filter now wired on the mobile dashboard. get_active_holds already accepts
-- p_agent_id (0079); this closes the gap so the tiles and the holds list agree.
--
-- The visible_user_ids() scope gate is PRESERVED — p_agent_id only narrows WITHIN
-- the caller's visibility, so passing an out-of-scope agent id yields an empty
-- result (never a cross-scope leak). Everything else (tenant gate, project filter,
-- period window, aggregate) is reproduced verbatim from the 0079 body.
--
-- Adding a defaulted 3rd param would create a SECOND overload get_booking_stats
-- (integer, uuid, uuid) alongside the existing (integer, uuid) → PostgREST calls
-- with p_period_days + p_project_id would become ambiguous. So DROP the 2-arg
-- version first, then CREATE the 3-arg one.
--
-- Prod head is 0095; this is 0096. File-based, `supabase db push --linked`. NEVER MCP apply.

DROP FUNCTION IF EXISTS public.get_booking_stats(integer, uuid);

CREATE OR REPLACE FUNCTION public.get_booking_stats(
  p_period_days integer DEFAULT 30,
  p_project_id  uuid    DEFAULT NULL,
  p_agent_id    uuid    DEFAULT NULL
)
RETURNS TABLE(
  confirmed_bookings integer,
  active_holds       integer,
  total_holds        integer,
  conversion_pct     numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
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
      AND (p_agent_id   IS NULL OR h.holding_agent_id = p_agent_id)
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
$function$;

REVOKE EXECUTE ON FUNCTION public.get_booking_stats(integer, uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_booking_stats(integer, uuid, uuid) TO authenticated;
