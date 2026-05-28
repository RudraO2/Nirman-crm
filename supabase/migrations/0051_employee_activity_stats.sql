-- Story 5.4 — Employee Activity Status
-- Admin-only RPC returning per-employee last action + today's activity counts.
-- SECURITY DEFINER, tenant-isolated, search_path = public, extensions.
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.get_employee_activity_stats()
RETURNS TABLE (
  employee_id               uuid,
  employee_name             text,
  last_action_at            timestamptz,
  leads_updated_today       int,
  followups_completed_today int
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
$$;

REVOKE ALL ON FUNCTION public.get_employee_activity_stats() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_employee_activity_stats() FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_employee_activity_stats() TO authenticated;
