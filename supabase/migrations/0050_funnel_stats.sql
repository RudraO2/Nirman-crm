-- Story 5.3 — Conversion Funnel Chart
-- Admin-only RPC returning 5 funnel stages with drop-off percentages.
-- SECURITY DEFINER, tenant-isolated, search_path = public, extensions.
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.get_funnel_stats(
  p_employee_id uuid DEFAULT NULL,
  p_project_id  uuid DEFAULT NULL,
  p_days        int  DEFAULT NULL
)
RETURNS TABLE (
  stage       text,
  lead_count  int,
  dropoff_pct numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_tz        text;
  v_today     date;
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') <> 'admin' THEN
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
    SELECT l.id, l.status, l.visit_date
    FROM   public.leads l
    WHERE  l.tenant_id = v_tenant_id
      AND  (p_employee_id IS NULL OR l.assigned_to_user_id = p_employee_id)
      AND  (p_project_id IS NULL OR EXISTS (
              SELECT 1
              FROM   public.lead_projects lp
              WHERE  lp.lead_id    = l.id
                AND  lp.project_id = p_project_id
           ))
      AND  (p_days IS NULL
            OR (l.created_at AT TIME ZONE v_tz)::date >= v_today - p_days)
  ),
  agg AS (
    SELECT
      COUNT(*)::int                                                        AS total,
      COUNT(*) FILTER (WHERE status = 'warm')::int                        AS warm,
      COUNT(*) FILTER (WHERE status = 'hot')::int                         AS hot,
      COUNT(*) FILTER (WHERE visit_date IS NOT NULL
                         AND visit_date < now())::int                      AS visited,
      COUNT(*) FILTER (WHERE status = 'sold')::int                        AS sold
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
    SELECT
      ord,
      stage_name,
      cnt,
      LAG(cnt) OVER (ORDER BY ord) AS prev_cnt
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
$$;

COMMENT ON FUNCTION public.get_funnel_stats(uuid, uuid, int) IS
  'Story 5.3 — Conversion funnel: Total → Warm → Hot → Visited → Sold with drop-off %. '
  'Filters: employee, project, days (NULL = all time, N = created_at within N days in tenant tz). '
  'Admin-only. SECURITY DEFINER.';

REVOKE EXECUTE ON FUNCTION public.get_funnel_stats(uuid, uuid, int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_funnel_stats(uuid, uuid, int) TO authenticated;
