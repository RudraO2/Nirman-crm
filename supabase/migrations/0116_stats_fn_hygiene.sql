-- 0116_stats_fn_hygiene.sql
-- Closes the three "open backend deferred items" tracked in project-state.md
-- (F-2 + ERRCODE + active-lead consistency). Bodies reproduced verbatim from
-- their latest definitions (0054 for the five admin stats fns +
-- get_employee_active_lead_counts; 0069 for the 4-arg get_funnel_stats) with
-- ONLY the targeted changes below. Same signatures → CREATE OR REPLACE, no
-- grant changes needed (existing grants survive OR REPLACE).
--
-- 1. F-2 date off-by-one: `>= v_today - p_days` spans p_days+1 calendar days
--    (p_days=1 covered yesterday AND today). Now `> v_today - p_days`, i.e.
--    "last N calendar days INCLUDING today" — the same window shape
--    get_pipeline_activity_14d always had (v_today-13 .. v_today = 14 days).
--    Affected: get_funnel_stats (created_at window),
--    get_employee_performance_stats (followup_window).
-- 2. ERRCODE 42501 on permission_denied: 6 fns raised bare
--    `RAISE EXCEPTION 'permission_denied'` (defaults to P0001) while the rest
--    of the codebase raises 42501 — clients matching on code missed these.
--    Message text unchanged, so message-matching clients keep working.
-- 3. Active-lead definition unified: get_employee_active_lead_counts used
--    `status IN ('hot','warm','cold')` while get_employee_active_lead_count and
--    get_employee_performance_stats use `status NOT IN ('dead','sold','future')`.
--    lead_status has exactly those 6 values today, so this is behavior-identical
--    — but NOT-IN is the canonical form (a future 7th status defaults to
--    "active" everywhere instead of silently diverging).
--
-- File-based migration; never MCP apply. Roll-forward only.

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. get_builder_home_metrics — ERRCODE only
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_builder_home_metrics()
 RETURNS TABLE(leads_today integer, leads_yesterday integer, followups_missed_today integer, followups_missed_yesterday integer, sold_this_month integer, sold_last_month integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_tz                    text;
  v_today                 date;
  v_yesterday             date;
  v_month_start           timestamp;
  v_last_month_start      timestamp;

  v_leads_today                int;
  v_leads_yesterday            int;
  v_followups_missed_today     int;
  v_followups_missed_yesterday int;
  v_sold_this_month            int;
  v_sold_last_month            int;
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(t.timezone, 'Asia/Kolkata') INTO v_tz
  FROM public.tenants t
  WHERE t.id = auth_tenant_id();
  IF v_tz IS NULL THEN
    v_tz := 'Asia/Kolkata';
  END IF;

  v_today            := (now() AT TIME ZONE v_tz)::date;
  v_yesterday        := v_today - 1;
  v_month_start      := date_trunc('month', now() AT TIME ZONE v_tz);
  v_last_month_start := date_trunc('month', (now() AT TIME ZONE v_tz) - interval '1 month');

  SELECT count(*) INTO v_leads_today
  FROM public.leads l
  WHERE (l.created_at AT TIME ZONE v_tz)::date = v_today;

  SELECT count(*) INTO v_leads_yesterday
  FROM public.leads l
  WHERE (l.created_at AT TIME ZONE v_tz)::date = v_yesterday;

  SELECT count(DISTINCT l.id) INTO v_followups_missed_today
  FROM public.leads l
  WHERE (l.next_followup_at AT TIME ZONE v_tz)::date = v_today
    AND l.next_followup_at < now()
    AND NOT EXISTS (
      SELECT 1 FROM public.lead_timeline t2
      WHERE t2.lead_id = l.id
        AND t2.occurred_at >= l.next_followup_at
    );

  SELECT count(DISTINCT l.id) INTO v_followups_missed_yesterday
  FROM public.leads l
  WHERE (l.next_followup_at AT TIME ZONE v_tz)::date = v_yesterday
    AND l.next_followup_at < now()
    AND NOT EXISTS (
      SELECT 1 FROM public.lead_timeline t2
      WHERE t2.lead_id = l.id
        AND t2.occurred_at >= l.next_followup_at
    );

  SELECT count(DISTINCT l.id) INTO v_sold_this_month
  FROM public.leads l
  JOIN public.lead_timeline t
    ON t.lead_id    = l.id
   AND t.event_type = 'status_changed'
   AND t.payload ->> 'to' = 'sold'
   AND (t.occurred_at AT TIME ZONE v_tz) >= v_month_start
  WHERE l.status = 'sold';

  SELECT count(DISTINCT l.id) INTO v_sold_last_month
  FROM public.leads l
  JOIN public.lead_timeline t
    ON t.lead_id    = l.id
   AND t.event_type = 'status_changed'
   AND t.payload ->> 'to' = 'sold'
   AND (t.occurred_at AT TIME ZONE v_tz) >= v_last_month_start
   AND (t.occurred_at AT TIME ZONE v_tz) <  v_month_start
  WHERE l.status = 'sold';

  RETURN QUERY
  SELECT
    v_leads_today,
    v_leads_yesterday,
    v_followups_missed_today,
    v_followups_missed_yesterday,
    v_sold_this_month,
    v_sold_last_month;
END;
$function$;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. get_employee_active_lead_counts — active filter unified (behavior-identical)
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_employee_active_lead_counts(p_user_ids uuid[])
 RETURNS TABLE(user_id uuid, active_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
BEGIN
  IF v_actor_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF p_user_ids IS NULL OR array_length(p_user_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT l.assigned_to_user_id AS user_id,
         count(*)::bigint       AS active_count
    FROM public.leads l
   WHERE l.tenant_id             = v_tenant_id
     AND l.assigned_to_user_id   = ANY(p_user_ids)
     AND l.status NOT IN ('dead', 'sold', 'future')
   GROUP BY l.assigned_to_user_id;
END;
$function$;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. get_employee_activity_stats — ERRCODE only
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_employee_activity_stats()
 RETURNS TABLE(employee_id uuid, employee_name text, last_action_at timestamp with time zone, leads_updated_today integer, followups_completed_today integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_tz        text;
  v_today     date;
  v_tenant_id uuid := auth_tenant_id();
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(t.timezone, 'Asia/Kolkata') INTO v_tz
  FROM   public.tenants t
  WHERE  t.id = v_tenant_id;
  IF v_tz IS NULL THEN v_tz := 'Asia/Kolkata'; END IF;

  v_today := (now() AT TIME ZONE v_tz)::date;

  RETURN QUERY
  WITH employees AS (
    SELECT u.id, u.email_or_username AS name
    FROM   public.users u
    WHERE  u.tenant_id = v_tenant_id
      AND  u.role      = 'employee'
      AND  u.is_active = true
  ),
  timeline_agg AS (
    SELECT
      l.assigned_to_user_id                                   AS emp_id,
      MAX(tl.occurred_at)                                     AS last_action_at,
      COUNT(DISTINCT l.id) FILTER (
        WHERE (tl.occurred_at AT TIME ZONE v_tz)::date = v_today
      )                                                       AS leads_updated_today
    FROM   public.lead_timeline tl
    JOIN   public.leads l
           ON l.id        = tl.lead_id
           AND l.tenant_id = v_tenant_id
           AND l.assigned_to_user_id IN (SELECT id FROM employees)
    GROUP  BY l.assigned_to_user_id
  ),
  followup_today AS (
    SELECT
      l.assigned_to_user_id AS emp_id,
      COUNT(*)              AS followups_done
    FROM   public.leads l
    WHERE  l.tenant_id              = v_tenant_id
      AND  l.assigned_to_user_id   IN (SELECT id FROM employees)
      AND  l.next_followup_at       IS NOT NULL
      AND  (l.next_followup_at AT TIME ZONE v_tz)::date = v_today
      AND  EXISTS (
             SELECT 1
             FROM   public.lead_timeline t2
             WHERE  t2.lead_id    = l.id
               AND  t2.occurred_at >= l.next_followup_at
           )
    GROUP  BY l.assigned_to_user_id
  )
  SELECT
    e.id                                          AS employee_id,
    e.name                                        AS employee_name,
    ta.last_action_at,
    COALESCE(ta.leads_updated_today, 0)::int      AS leads_updated_today,
    COALESCE(ft.followups_done,      0)::int      AS followups_completed_today
  FROM       employees     e
  LEFT JOIN  timeline_agg  ta ON ta.emp_id = e.id
  LEFT JOIN  followup_today ft ON ft.emp_id = e.id
  ORDER BY   ta.last_action_at DESC NULLS LAST;
END;
$function$;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. get_employee_performance_stats — ERRCODE + F-2 window fix
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_employee_performance_stats(p_days integer DEFAULT 30)
 RETURNS TABLE(employee_id uuid, employee_name text, active_leads integer, warm_count integer, cold_count integer, hot_count integer, dead_count integer, sold_count integer, future_count integer, followups_completed integer, followups_missed integer, total_assigned integer, conversion_rate numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_tz          text;
  v_today       date;
  v_month_start timestamp;
  v_tenant_id   uuid := auth_tenant_id();
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
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
  -- Leads with a followup due in the last p_days calendar days incl today
  -- (0116: was `>= v_today - p_days`, an off-by-one — p_days=1 spanned 2 days)
  followup_window AS (
    SELECT l.id, l.assigned_to_user_id, l.next_followup_at
    FROM   public.leads l
    WHERE  l.tenant_id           = v_tenant_id
      AND  l.assigned_to_user_id IN (SELECT id FROM employees)
      AND  l.next_followup_at IS NOT NULL
      AND  (l.next_followup_at AT TIME ZONE v_tz)::date > v_today - p_days
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
$function$;

-- ────────────────────────────────────────────────────────────────────────────
-- 5. get_funnel_stats (4-arg, latest def = 0069) — ERRCODE + F-2 window fix
-- ────────────────────────────────────────────────────────────────────────────
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
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
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
      -- 0116: was `>= v_today - p_days`, an off-by-one — p_days=1 spanned 2 days
      AND  (p_days IS NULL
            OR (l.created_at AT TIME ZONE v_tz)::date > v_today - p_days)
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

-- ────────────────────────────────────────────────────────────────────────────
-- 6. get_lead_status_distribution — ERRCODE only
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_lead_status_distribution()
 RETURNS TABLE(status text, lead_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_tenant_id uuid := auth_tenant_id();
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
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
$function$;

-- ────────────────────────────────────────────────────────────────────────────
-- 7. get_pipeline_activity_14d — ERRCODE only
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_pipeline_activity_14d()
 RETURNS TABLE(day date, new_leads integer, status_changes integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_tz        text;
  v_today     date;
  v_tenant_id uuid := auth_tenant_id();
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
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
$function$;

COMMIT;
