-- 0054_harden_admin_role_guards.sql
-- Story 8.1 (Epic 8) — F-1 / Architecture Decision 35.
--
-- Hardens every admin-only SECURITY DEFINER function against a NULL/absent
-- JWT role claim. SQL three-valued logic makes the existing deny-guards
-- NULL-permissive:
--   (auth.jwt()->'app_metadata'->>'role') <> 'admin'   -- NULL <> 'admin'  => NULL => IF skipped => ALLOWED
--   v_actor_role NOT IN ('admin', ...)                 -- NULL NOT IN (..) => NULL => IF skipped => ALLOWED
-- Today every authenticated user carries a stamped role, so this is latent.
-- Story 8.3 (public self-serve sign-up) creates a momentarily role-less
-- auth.users row, turning this into a real privilege/cross-tenant hole.
-- Fix: scalar guards use NULL-safe `IS DISTINCT FROM 'admin'`; set-membership
-- guards wrap the operand in COALESCE(role,'') so a NULL role is denied.
--
-- AFFECTED FUNCTIONS (17) — re-created with hardened guards, bodies otherwise
-- byte-for-byte identical to their current definition:
--   scalar `<> 'admin'` -> `IS DISTINCT FROM 'admin'` (15):
--     assign_lead, bulk_assign_leads, get_builder_home_metrics,
--     get_employee_active_lead_count, get_employee_active_lead_counts,
--     get_employee_activity_stats, get_employee_performance_stats,
--     get_funnel_stats, get_future_pool_match_count,
--     get_lead_status_distribution, get_pipeline_activity_14d,
--     list_assignable_leads, list_employees_for_assignment,
--     reactivate_future_leads, search_leads_global
--   `NOT IN (...)` -> `COALESCE(role,'') NOT IN (...)` (2):
--     get_lead_name_for_notification (NOT IN ('admin','service_role')),
--     list_employees_for_share        (NOT IN ('employee','admin'))
--
-- INTENTIONALLY UNCHANGED (already NULL-safe — no behavioral churn):
--   bulk_import_leads, check_phone_hashes, export_leads_data, get_export_count
--     -- already guard with `IS DISTINCT FROM 'admin'`.
--   revoke_share -- positive branches `= 'employee'`/`= 'admin'` with an
--     explicit ELSE that RAISEs permission_denied; a NULL role matches no
--     branch and is already denied.
--   Table RLS policies (e.g. whatsapp_templates) use the safe `= 'admin'`
--     positive form and are NOT touched by this migration.

BEGIN;

-- 1. assign_lead --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assign_lead(p_lead_id uuid, p_target_user_id uuid, p_deadline timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor_id    uuid := auth.uid();
  v_actor_role  text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id   uuid := public.auth_tenant_id();
  v_prev_user   uuid;
  v_prev_uname  text;
  v_target      RECORD;
  v_share       RECORD;
  v_timeline_id uuid;
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF v_actor_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'tenant_missing' USING ERRCODE = '42501';
  END IF;

  SELECT assigned_to_user_id
    INTO v_prev_user
    FROM public.leads
   WHERE id = p_lead_id AND tenant_id = v_tenant_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'lead_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT id, role, is_active, email_or_username
    INTO v_target
    FROM public.users
   WHERE id = p_target_user_id AND tenant_id = v_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'target_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_target.role <> 'employee' OR v_target.is_active = false THEN
    RAISE EXCEPTION 'target_not_assignable' USING ERRCODE = '22023';
  END IF;

  UPDATE public.leads
     SET assigned_to_user_id = p_target_user_id,
         assignment_deadline = p_deadline,
         updated_at          = now()
   WHERE id = p_lead_id AND tenant_id = v_tenant_id;

  -- Cascade-revoke shares (system actor) — mirror log_timeline_event by writing
  -- BOTH lead_timeline AND domain_events so downstream consumers stay in sync.
  FOR v_share IN
    DELETE FROM public.lead_shares
     WHERE lead_id = p_lead_id
   RETURNING recipient_user_id
  LOOP
    INSERT INTO public.lead_timeline (
      tenant_id, lead_id, actor_user_id, actor_role, event_type, payload, occurred_at
    ) VALUES (
      v_tenant_id, p_lead_id, NULL, 'system',
      'share_revoked',
      jsonb_build_object(
        'recipient_user_id', v_share.recipient_user_id,
        'reason',            'cascade_on_assign'
      ),
      now()
    )
    RETURNING id INTO v_timeline_id;

    INSERT INTO public.domain_events (
      tenant_id, event_type, payload, occurred_at
    ) VALUES (
      v_tenant_id,
      'share_revoked',
      jsonb_build_object(
        'lead_id',       p_lead_id,
        'actor_user_id', NULL,
        'actor_role',    'system',
        'timeline_id',   v_timeline_id,
        'event_payload', jsonb_build_object(
          'recipient_user_id', v_share.recipient_user_id,
          'reason',            'cascade_on_assign'
        )
      ),
      now()
    );
  END LOOP;

  IF v_prev_user IS NULL THEN
    PERFORM public.log_timeline_event(
      p_lead_id,
      'assigned'::public.timeline_event_type,
      jsonb_build_object(
        'to',          p_target_user_id,
        'to_username', v_target.email_or_username,
        'deadline',    p_deadline
      )
    );
  ELSIF v_prev_user <> p_target_user_id THEN
    SELECT email_or_username INTO v_prev_uname
      FROM public.users WHERE id = v_prev_user;
    PERFORM public.log_timeline_event(
      p_lead_id,
      'reassigned'::public.timeline_event_type,
      jsonb_build_object(
        'from',          v_prev_user,
        'from_username', v_prev_uname,
        'to',            p_target_user_id,
        'to_username',   v_target.email_or_username,
        'deadline',      p_deadline
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'lead_id',      p_lead_id,
    'prev_user_id', v_prev_user,
    'new_user_id',  p_target_user_id,
    'deadline',     p_deadline
  );
END;
$function$;

-- 2. bulk_assign_leads --------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bulk_assign_leads(p_assignments jsonb, p_deadline timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_item       jsonb;
  v_lead_id    uuid;
  v_user_id    uuid;
  v_assigned   int  := 0;
  v_per_emp    jsonb := '{}'::jsonb;
  v_prev_count int;
BEGIN
  IF v_actor_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF p_assignments IS NULL OR jsonb_typeof(p_assignments) <> 'array' THEN
    RAISE EXCEPTION 'invalid_assignments' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_assignments) = 0 THEN
    RAISE EXCEPTION 'empty_assignments' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_assignments) > 500 THEN
    RAISE EXCEPTION 'too_many_assignments' USING ERRCODE = '22023';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_assignments) LOOP
    v_lead_id := (v_item->>'lead_id')::uuid;
    v_user_id := (v_item->>'target_user_id')::uuid;

    IF v_lead_id IS NULL OR v_user_id IS NULL THEN
      RAISE EXCEPTION 'malformed_assignment_item' USING ERRCODE = '22023';
    END IF;

    -- Delegate to assign_lead — handles auth check, timeline, cascade-revoke.
    -- assign_lead re-reads auth.uid()/auth.jwt() which remain valid in this session.
    PERFORM public.assign_lead(v_lead_id, v_user_id, p_deadline);
    v_assigned := v_assigned + 1;

    -- Accumulate per-employee count for notification fan-out.
    v_prev_count := COALESCE((v_per_emp->>(v_user_id::text))::int, 0);
    v_per_emp    := jsonb_set(v_per_emp, ARRAY[v_user_id::text], to_jsonb(v_prev_count + 1));
  END LOOP;

  RETURN jsonb_build_object(
    'assigned',      v_assigned,
    'per_employee',  v_per_emp
  );
END;
$function$;

-- 3. get_builder_home_metrics -------------------------------------------------
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
    RAISE EXCEPTION 'permission_denied';
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

-- 4. get_employee_active_lead_count -------------------------------------------
CREATE OR REPLACE FUNCTION public.get_employee_active_lead_count(p_employee_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor_role  text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id   uuid := public.auth_tenant_id();
  v_count       int;
BEGIN
  IF v_actor_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  -- Validate employee belongs to caller's tenant with role='employee'
  IF NOT EXISTS (
    SELECT 1 FROM public.users
     WHERE id        = p_employee_id
       AND tenant_id = v_tenant_id
       AND role      = 'employee'
  ) THEN
    RAISE EXCEPTION 'employee_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT COUNT(*)::int
    INTO v_count
    FROM public.leads
   WHERE assigned_to_user_id = p_employee_id
     AND tenant_id           = v_tenant_id
     AND status NOT IN ('dead', 'sold', 'future');

  RETURN v_count;
END;
$function$;

-- 5. get_employee_active_lead_counts ------------------------------------------
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
     AND l.status::text         IN ('hot', 'warm', 'cold')
   GROUP BY l.assigned_to_user_id;
END;
$function$;

-- 6. get_employee_activity_stats ----------------------------------------------
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
    RAISE EXCEPTION 'permission_denied';
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

-- 7. get_employee_performance_stats -------------------------------------------
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
$function$;

-- 8. get_funnel_stats ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_funnel_stats(p_employee_id uuid DEFAULT NULL::uuid, p_project_id uuid DEFAULT NULL::uuid, p_days integer DEFAULT NULL::integer)
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
$function$;

-- 9. get_future_pool_match_count ----------------------------------------------
CREATE OR REPLACE FUNCTION public.get_future_pool_match_count(p_property_type text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor_role  text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id   uuid := public.auth_tenant_id();
  v_count       int;
BEGIN
  IF v_actor_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT COUNT(*)::int
    INTO v_count
    FROM public.leads
   WHERE tenant_id     = v_tenant_id
     AND status        = 'future'
     AND interest_type = p_property_type;

  RETURN COALESCE(v_count, 0);
END;
$function$;

-- 10. get_lead_status_distribution --------------------------------------------
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
$function$;

-- 11. get_pipeline_activity_14d -----------------------------------------------
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
$function$;

-- 12. list_assignable_leads ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_assignable_leads(p_q text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_employee uuid DEFAULT NULL::uuid, p_include_archived boolean DEFAULT false, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_unassigned_only boolean DEFAULT false)
 RETURNS TABLE(id uuid, name text, phone_last4 text, status text, assigned_to_user_id uuid, assignee_username text, assignment_deadline timestamp with time zone, created_at timestamp with time zone, total_count bigint, interest_type text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'vault'
AS $function$
DECLARE
  v_actor_id    uuid := auth.uid();
  v_actor_role  text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id   uuid := public.auth_tenant_id();
  v_pii_key     text;
  v_q           text;
  v_q_escaped   text;
  v_phone       text;
  v_phone_hash  text;
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF v_actor_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT s.decrypted_secret INTO v_pii_key
    FROM vault.decrypted_secrets s
   WHERE s.name = 'lead_pii_key' LIMIT 1;
  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing';
  END IF;

  v_q := NULLIF(trim(COALESCE(p_q, '')), '');
  IF v_q IS NOT NULL THEN
    v_q_escaped := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
    v_phone := public.normalize_phone(v_q);
    IF v_phone IS NOT NULL THEN
      v_phone_hash := encode(extensions.digest(v_phone, 'sha256'), 'hex');
    END IF;
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT
      l.id,
      l.status::text                                                        AS status,
      CASE WHEN l.name_encrypted IS NOT NULL
           THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
           ELSE NULL END                                                    AS name,
      right(extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key), 4)  AS phone_last4,
      l.phone_hash,
      l.assigned_to_user_id,
      u.email_or_username                                                   AS assignee_username,
      l.assignment_deadline,
      l.created_at,
      l.interest_type
    FROM public.leads l
    LEFT JOIN public.users u ON u.id = l.assigned_to_user_id
    WHERE l.tenant_id = v_tenant_id
      AND (p_include_archived OR l.status IN ('hot','warm','cold'))
      AND (p_status IS NULL OR l.status::text = p_status)
      AND (NOT p_unassigned_only OR l.assigned_to_user_id IS NULL)
      AND (p_employee IS NULL OR l.assigned_to_user_id = p_employee)
  ),
  filtered AS (
    SELECT b.*
    FROM base b
    WHERE v_q IS NULL
       OR (b.name IS NOT NULL AND b.name ILIKE '%' || v_q_escaped || '%' ESCAPE '\')
       OR (v_phone_hash IS NOT NULL AND b.phone_hash = v_phone_hash)
  ),
  counted AS (
    SELECT count(*) AS total FROM filtered
  )
  SELECT
    f.id, f.name, f.phone_last4, f.status,
    f.assigned_to_user_id, f.assignee_username, f.assignment_deadline,
    f.created_at, c.total, f.interest_type
  FROM filtered f, counted c
  ORDER BY f.assignment_deadline ASC NULLS LAST, f.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$function$;

-- 13. list_employees_for_assignment -------------------------------------------
CREATE OR REPLACE FUNCTION public.list_employees_for_assignment()
 RETURNS TABLE(id uuid, username text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
BEGIN
  IF v_actor_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT u.id, u.email_or_username
    FROM public.users u
   WHERE u.tenant_id = v_tenant_id
     AND u.role      = 'employee'
     AND u.is_active = true
   ORDER BY u.email_or_username ASC;
END;
$function$;

-- 14. reactivate_future_leads -------------------------------------------------
CREATE OR REPLACE FUNCTION public.reactivate_future_leads(p_leads jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor_id    uuid := auth.uid();
  v_actor_role  text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id   uuid := public.auth_tenant_id();
  v_entry       jsonb;
  v_lead_id     uuid;
  v_employee_id uuid;
  v_affected    int;
  v_count       int := 0;
BEGIN
  -- P1-A: Require authenticated caller (consistent with all other RPCs in this codebase)
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF v_actor_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'tenant_missing' USING ERRCODE = '42501';
  END IF;

  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_leads)
  LOOP
    v_lead_id     := (v_entry ->> 'lead_id')::uuid;
    v_employee_id := (v_entry ->> 'employee_id')::uuid;

    -- P1-B: Reject null employee_id before touching any lead rows
    IF v_employee_id IS NULL THEN
      RAISE EXCEPTION 'employee_id_required for lead: %', v_lead_id;
    END IF;

    UPDATE public.leads
       SET status     = 'warm',
           updated_at = now()
     WHERE id         = v_lead_id
       AND tenant_id  = v_tenant_id
       AND status     = 'future';

    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected = 0 THEN
      RAISE EXCEPTION 'lead_not_found_or_not_future: %', v_lead_id;
    END IF;

    PERFORM public.log_timeline_event(
      v_lead_id,
      'status_changed'::public.timeline_event_type,
      jsonb_build_object('from', 'future', 'to', 'warm', 'restored', true)
    );

    PERFORM public.assign_lead(v_lead_id, v_employee_id, NULL::timestamptz);

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('reactivated', v_count);
END;
$function$;

-- 15. search_leads_global -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.search_leads_global(p_q text, p_limit integer DEFAULT 50)
 RETURNS TABLE(id uuid, name text, phone_last4 text, status text, assigned_to_user_id uuid, assignee_username text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'vault'
AS $function$
DECLARE
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
  v_pii_key    text;
  v_q          text;
  v_q_escaped  text;
  v_phone      text;
  v_phone_hash text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF v_actor_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_q := NULLIF(trim(COALESCE(p_q, '')), '');
  IF v_q IS NULL THEN
    RETURN;
  END IF;

  SELECT s.decrypted_secret INTO v_pii_key
    FROM vault.decrypted_secrets s
   WHERE s.name = 'lead_pii_key' LIMIT 1;
  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing';
  END IF;

  -- Determine branch: phone or name.
  v_phone := public.normalize_phone(v_q);
  IF v_phone IS NOT NULL THEN
    -- Phone branch: hash lookup, O(1), decrypt only matching rows.
    v_phone_hash := encode(extensions.digest(v_phone, 'sha256'), 'hex');
    RETURN QUERY
    SELECT
      l.id,
      CASE WHEN l.name_encrypted IS NOT NULL
           THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
           ELSE NULL END                                                 AS name,
      right(extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key), 4) AS phone_last4,
      l.status::text                                                      AS status,
      l.assigned_to_user_id,
      u.email_or_username                                                 AS assignee_username
    FROM public.leads l
    LEFT JOIN public.users u ON u.id = l.assigned_to_user_id
    WHERE l.tenant_id  = v_tenant_id
      AND l.phone_hash = v_phone_hash
    LIMIT p_limit;
  ELSE
    -- Name branch: decrypt + ILIKE across all statuses including archived.
    v_q_escaped := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
    RETURN QUERY
    SELECT
      l.id,
      extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)              AS name,
      right(extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key), 4)   AS phone_last4,
      l.status::text                                                         AS status,
      l.assigned_to_user_id,
      u.email_or_username                                                    AS assignee_username
    FROM public.leads l
    LEFT JOIN public.users u ON u.id = l.assigned_to_user_id
    WHERE l.tenant_id      = v_tenant_id
      AND l.name_encrypted IS NOT NULL
      AND extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
            ILIKE '%' || v_q_escaped || '%' ESCAPE '\'
    LIMIT p_limit;
  END IF;
END;
$function$;

-- 16. get_lead_name_for_notification ------------------------------------------
-- NOT IN guard: wrap v_actor_role in COALESCE so a NULL app_metadata role is
-- treated as '' (not in the allow-set) => denied. Service-role path preserved.
CREATE OR REPLACE FUNCTION public.get_lead_name_for_notification(p_lead_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'vault'
AS $function$
DECLARE
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_pii_key    text;
  v_name       text;
BEGIN
  -- Allow admin (UI) OR service_role (edge fn) callers
  IF COALESCE(v_actor_role, '') NOT IN ('admin', 'service_role') AND
     COALESCE((auth.jwt() ->> 'role'), '') <> 'service_role' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT s.decrypted_secret INTO v_pii_key
    FROM vault.decrypted_secrets s
   WHERE s.name = 'lead_pii_key' LIMIT 1;
  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing';
  END IF;

  SELECT CASE WHEN l.name_encrypted IS NOT NULL
              THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
              ELSE 'New lead' END
    INTO v_name
    FROM public.leads l
   WHERE l.id = p_lead_id;

  RETURN COALESCE(v_name, 'New lead');
END;
$function$;

-- 17. list_employees_for_share ------------------------------------------------
-- NOT IN guard: wrap v_actor_role in COALESCE so a NULL role is denied.
CREATE OR REPLACE FUNCTION public.list_employees_for_share()
 RETURNS TABLE(id uuid, username text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor_id   uuid := auth.uid();
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF COALESCE(v_actor_role, '') NOT IN ('employee', 'admin') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT u.id, u.email_or_username
    FROM public.users u
   WHERE u.tenant_id = v_tenant_id
     AND u.role      = 'employee'
     AND u.is_active = true
     AND u.id        <> v_actor_id
   ORDER BY u.email_or_username ASC;
END;
$function$;

COMMIT;
