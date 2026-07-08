-- 0069_visit_funnel.sql
-- Story 13.7 (Epic 13) — FR-46/FR-24/FR-45. Visit-count funnel + source analytics.
--
-- 1. Backfill visit_count = 1 for historic leads that already have a past visit_date, so the
--    funnel's redefined "Visited" stage preserves historical numbers (retroactive decision).
-- 2. get_funnel_stats: "Visited" switches from (visit_date in past) to (visit_count > 0), and
--    gains an optional p_source filter (FR-45). Signature changes (adds p_source) → DROP+CREATE.
--    Body reproduced from 0054; only the visited predicate, the source filter, and the param added.
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

-- 1. Retroactive backfill — preserve historical "Visited" counts.
UPDATE public.leads
   SET visit_count = 1
 WHERE visit_count = 0
   AND visit_date IS NOT NULL
   AND visit_date < now();

-- 2. get_funnel_stats — visit_count-based Visited + source filter.
DROP FUNCTION IF EXISTS public.get_funnel_stats(uuid, uuid, integer);

CREATE OR REPLACE FUNCTION public.get_funnel_stats(
  p_employee_id uuid    DEFAULT NULL,
  p_project_id  uuid    DEFAULT NULL,
  p_days        integer DEFAULT NULL,
  p_source      text    DEFAULT NULL
)
RETURNS TABLE(stage text, lead_count integer, dropoff_pct numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_tenant_id uuid;
  v_tz        text;
  v_today     date;
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  v_tenant_id := auth_tenant_id();

  SELECT COALESCE(t.timezone, 'Asia/Kolkata') INTO v_tz
  FROM   public.tenants t
  WHERE  t.id = v_tenant_id;
  IF v_tz IS NULL THEN v_tz := 'Asia/Kolkata'; END IF;

  v_today := (now() AT TIME ZONE v_tz)::date;

  RETURN QUERY
  WITH base_leads AS (
    SELECT l.id, l.status, l.visit_count
    FROM   public.leads l
    WHERE  l.tenant_id = v_tenant_id
      AND  (p_employee_id IS NULL OR l.assigned_to_user_id = p_employee_id)
      AND  (p_project_id IS NULL OR EXISTS (
              SELECT 1
              FROM   public.lead_projects lp
              WHERE  lp.lead_id    = l.id
                AND  lp.project_id = p_project_id
           ))
      AND  (p_source IS NULL OR l.source::text = p_source)
      AND  (p_days IS NULL
            OR (l.created_at AT TIME ZONE v_tz)::date >= v_today - p_days)
  ),
  agg AS (
    SELECT
      COUNT(*)::int                                            AS total,
      COUNT(*) FILTER (WHERE status = 'warm')::int            AS warm,
      COUNT(*) FILTER (WHERE status = 'hot')::int             AS hot,
      COUNT(*) FILTER (WHERE visit_count > 0)::int            AS visited,
      COUNT(*) FILTER (WHERE status = 'sold')::int            AS sold
    FROM base_leads
  ),
  stages AS (
    SELECT 1 AS ord, 'total'::text   AS stage_name, total   AS cnt FROM agg
    UNION ALL
    SELECT 2,        'warm'::text,                  warm            FROM agg
    UNION ALL
    SELECT 3,        'hot'::text,                   hot             FROM agg
    UNION ALL
    SELECT 4,        'visited'::text,               visited         FROM agg
    UNION ALL
    SELECT 5,        'sold'::text,                  sold            FROM agg
  ),
  with_prev AS (
    SELECT ord, stage_name, cnt, LAG(cnt) OVER (ORDER BY ord) AS prev_cnt
    FROM stages
  )
  SELECT
    stage_name                                                             AS stage,
    cnt                                                                    AS lead_count,
    CASE
      WHEN ord = 1 THEN NULL
      ELSE ROUND((prev_cnt - cnt)::numeric * 100.0 / NULLIF(prev_cnt, 0), 1)
    END                                                                    AS dropoff_pct
  FROM  with_prev
  ORDER BY ord;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_funnel_stats(uuid, uuid, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_funnel_stats(uuid, uuid, integer, text) TO authenticated;

COMMENT ON FUNCTION public.get_funnel_stats(uuid, uuid, integer, text) IS
  'Story 5.3 + 13.7 — conversion funnel total→warm→hot→visited→sold with drop-off %. Visited = visit_count > 0 (FR-46). Filters: employee, project, days, source (FR-45). Admin-only.';

COMMIT;
