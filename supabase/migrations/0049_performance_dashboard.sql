-- Story 5.2 — Per-Employee Performance Dashboard
-- Three admin-only RPCs for the performance analytics page.
-- All SECURITY DEFINER, tenant-isolated, search_path = public, extensions.
-- Roll-forward only. Never edit after apply.

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. get_employee_performance_stats(p_days int DEFAULT 30)
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_employee_performance_stats(
  p_days int DEFAULT 30
)
RETURNS TABLE (
  employee_id         uuid,
  employee_name       text,
  active_leads        int,
  warm_count          int,
  cold_count          int,
  hot_count           int,
  dead_count          int,
  sold_count          int,
  future_count        int,
  followups_completed int,
  followups_missed    int,
  total_assigned      int,
  conversion_rate     numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tz          text;
  v_today       date;
  v_month_start timestamp;
  v_tenant_id   uuid := auth_tenant_id();
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  SELECT COALESCE(t.timezone, 'Asia/Kolkata') INTO v_tz
  FROM public.tenants t
  WHERE t.id = v_tenant_id;
  IF v_tz IS NULL THEN v_tz := 'Asia/Kolkata'; END IF;

  v_today       := (now() AT TIME ZONE v_tz)::date;
  v_month_start := date_trunc('month', now() AT TIME ZONE v_tz);

  RETURN QUERY
  WITH employees AS (
    SELECT u.id, u.email_or_username AS name
    FROM   public.users u
    WHERE  u.tenant_id = v_tenant_id
      AND  u.role      = 'employee'
      AND  u.is_active = true
  ),
  -- Per-employee lead counts by status (single scan)
  lead_stats AS (
    SELECT
      l.assigned_to_user_id                                              AS uid,
      COUNT(*) FILTER (WHERE l.status NOT IN ('dead','sold','future'))::int AS active_leads,
      COUNT(*) FILTER (WHERE l.status = 'warm')::int                    AS warm_count,
      COUNT(*) FILTER (WHERE l.status = 'cold')::int                    AS cold_count,
      COUNT(*) FILTER (WHERE l.status = 'hot')::int                     AS hot_count,
      COUNT(*) FILTER (WHERE l.status = 'dead')::int                    AS dead_count,
      COUNT(*) FILTER (WHERE l.status = 'sold')::int                    AS sold_count,
      COUNT(*) FILTER (WHERE l.status = 'future')::int                  AS future_count,
      COUNT(*)::int                                                      AS total_assigned
    FROM public.leads l
    WHERE l.tenant_id           = v_tenant_id
      AND l.assigned_to_user_id IN (SELECT id FROM employees)
    GROUP BY l.assigned_to_user_id
  ),
  -- Leads with a followup due within [today-p_days, today] in tenant tz
  followup_window AS (
    SELECT l.id, l.assigned_to_user_id, l.next_followup_at
    FROM   public.leads l
    WHERE  l.tenant_id           = v_tenant_id
      AND  l.assigned_to_user_id IN (SELECT id FROM employees)
      AND  l.next_followup_at IS NOT NULL
      AND  (l.next_followup_at AT TIME ZONE v_tz)::date >= v_today - p_days
      AND  (l.next_followup_at AT TIME ZONE v_tz)::date <= v_today
  ),
  -- Aggregate completed + missed per employee
  followup_stats AS (
    SELECT
      fw.assigned_to_user_id AS uid,
      COUNT(*) FILTER (
        WHERE EXISTS (
          SELECT 1 FROM public.lead_timeline t2
          WHERE  t2.lead_id     = fw.id
            AND  t2.occurred_at >= fw.next_followup_at
        )
      )::int AS followups_completed,
      COUNT(*) FILTER (
        WHERE fw.next_followup_at < now()
          AND NOT EXISTS (
            SELECT 1 FROM public.lead_timeline t2
            WHERE  t2.lead_id     = fw.id
              AND  t2.occurred_at >= fw.next_followup_at
          )
      )::int AS followups_missed
    FROM followup_window fw
    GROUP BY fw.assigned_to_user_id
  ),
  -- Leads sold in current calendar month (tenant tz), same pattern as 0030
  sold_month AS (
    SELECT l.assigned_to_user_id AS uid, COUNT(DISTINCT l.id)::int AS cnt
    FROM   public.leads l
    WHERE  l.tenant_id           = v_tenant_id
      AND  l.status              = 'sold'
      AND  l.assigned_to_user_id IN (SELECT id FROM employees)
      AND  EXISTS (
             SELECT 1
             FROM   public.lead_timeline tl
             WHERE  tl.lead_id      = l.id
               AND  tl.event_type   = 'status_changed'
               AND  tl.payload ->> 'to' = 'sold'
               AND  (tl.occurred_at AT TIME ZONE v_tz) >= v_month_start
           )
    GROUP BY l.assigned_to_user_id
  )
  SELECT
    e.id,
    e.name,
    COALESCE(ls.active_leads,        0),
    COALESCE(ls.warm_count,          0),
    COALESCE(ls.cold_count,          0),
    COALESCE(ls.hot_count,           0),
    COALESCE(ls.dead_count,          0),
    COALESCE(ls.sold_count,          0),
    COALESCE(ls.future_count,        0),
    COALESCE(fs.followups_completed, 0),
    COALESCE(fs.followups_missed,    0),
    COALESCE(ls.total_assigned,      0),
    ROUND(
      100.0 * COALESCE(sm.cnt, 0) / NULLIF(COALESCE(ls.total_assigned, 0), 0),
      1
    )
  FROM employees e
  LEFT JOIN lead_stats    ls ON ls.uid = e.id
  LEFT JOIN followup_stats fs ON fs.uid = e.id
  LEFT JOIN sold_month    sm ON sm.uid = e.id
  ORDER BY COALESCE(ls.active_leads, 0) DESC;
END;
$$;

COMMENT ON FUNCTION public.get_employee_performance_stats(int) IS
  'Story 5.2 — Per-employee stats for admin performance dashboard. p_days controls followup window (default 30). Tenant-tz date buckets. Admin-only. SECURITY DEFINER.';

REVOKE EXECUTE ON FUNCTION public.get_employee_performance_stats(int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_employee_performance_stats(int) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. get_pipeline_activity_14d()
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_pipeline_activity_14d()
RETURNS TABLE (
  day            date,
  new_leads      int,
  status_changes int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tz        text;
  v_today     date;
  v_tenant_id uuid := auth_tenant_id();
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  SELECT COALESCE(t.timezone, 'Asia/Kolkata') INTO v_tz
  FROM   public.tenants t
  WHERE  t.id = v_tenant_id;
  IF v_tz IS NULL THEN v_tz := 'Asia/Kolkata'; END IF;

  v_today := (now() AT TIME ZONE v_tz)::date;

  RETURN QUERY
  WITH days AS (
    SELECT d::date AS day
    FROM   generate_series(
             (v_today - 13)::timestamp,
             v_today::timestamp,
             '1 day'::interval
           ) d
  ),
  new_leads_by_day AS (
    SELECT (l.created_at AT TIME ZONE v_tz)::date AS day,
           COUNT(*)::int AS cnt
    FROM   public.leads l
    WHERE  l.tenant_id = v_tenant_id
      AND  (l.created_at AT TIME ZONE v_tz)::date >= v_today - 13
      AND  (l.created_at AT TIME ZONE v_tz)::date <= v_today
    GROUP BY 1
  ),
  status_changes_by_day AS (
    SELECT (tl.occurred_at AT TIME ZONE v_tz)::date AS day,
           COUNT(*)::int AS cnt
    FROM   public.lead_timeline tl
    JOIN   public.leads l ON l.id = tl.lead_id AND l.tenant_id = v_tenant_id
    WHERE  tl.event_type = 'status_changed'
      AND  (tl.occurred_at AT TIME ZONE v_tz)::date >= v_today - 13
      AND  (tl.occurred_at AT TIME ZONE v_tz)::date <= v_today
    GROUP BY 1
  )
  SELECT
    d.day,
    COALESCE(nl.cnt, 0) AS new_leads,
    COALESCE(sc.cnt, 0) AS status_changes
  FROM  days d
  LEFT JOIN new_leads_by_day     nl ON nl.day = d.day
  LEFT JOIN status_changes_by_day sc ON sc.day = d.day
  ORDER BY d.day;
END;
$$;

COMMENT ON FUNCTION public.get_pipeline_activity_14d() IS
  'Story 5.2 — Last 14 days pipeline activity: new leads + status changes per day in tenant tz. Zero-fills days with no activity. Admin-only. SECURITY DEFINER.';

REVOKE EXECUTE ON FUNCTION public.get_pipeline_activity_14d() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_pipeline_activity_14d() TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. get_lead_status_distribution()
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_lead_status_distribution()
RETURNS TABLE (
  status     text,
  lead_count int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid := auth_tenant_id();
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  RETURN QUERY
  WITH all_statuses AS (
    SELECT unnest(ARRAY['warm','cold','hot','dead','sold','future']) AS status
  ),
  counts AS (
    SELECT l.status::text AS status, COUNT(*)::int AS lead_count
    FROM   public.leads l
    WHERE  l.tenant_id = v_tenant_id
    GROUP  BY l.status
  )
  SELECT s.status, COALESCE(c.lead_count, 0)::int
  FROM   all_statuses s
  LEFT JOIN counts c ON c.status = s.status
  ORDER  BY s.status;
END;
$$;

COMMENT ON FUNCTION public.get_lead_status_distribution() IS
  'Story 5.2 — Current lead status distribution across all 6 statuses. Zero-fills statuses with no leads. Admin-only. SECURITY DEFINER.';

REVOKE EXECUTE ON FUNCTION public.get_lead_status_distribution() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_lead_status_distribution() TO authenticated;
