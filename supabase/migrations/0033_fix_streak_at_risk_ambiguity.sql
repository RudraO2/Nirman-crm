-- Story 7.3 fix — streak_at_risk_targets() raised "column reference tenant_id is ambiguous"
-- because RETURNS TABLE OUT params (tenant_id, token, …) collide with unqualified column
-- references inside the CTEs. Add `#variable_conflict use_column` so ambiguous identifiers
-- resolve to columns. Roll-forward only.

CREATE OR REPLACE FUNCTION public.streak_at_risk_targets()
RETURNS TABLE (
  user_id     uuid,
  tenant_id   uuid,
  local_date  date,
  streak_days int,
  token       text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
#variable_conflict use_column
BEGIN
  RETURN QUERY
  WITH due_tenants AS (
    SELECT t.id AS tenant_id,
           t.timezone AS tz,
           (now() AT TIME ZONE t.timezone)::date AS local_today
    FROM public.tenants t
    WHERE extract(hour FROM (now() AT TIME ZONE t.timezone))::int = 18
  ),
  emp AS (
    SELECT u.id AS uid, u.tenant_id, d.tz, d.local_today
    FROM public.users u
    JOIN due_tenants d ON d.tenant_id = u.tenant_id
    WHERE u.role = 'employee'
  ),
  acts AS (
    SELECT e.uid, e.tenant_id, e.local_today,
           (t.occurred_at AT TIME ZONE e.tz)::date AS d
    FROM emp e
    JOIN public.lead_timeline t
      ON t.actor_user_id = e.uid
     AND t.event_type IN (
           'status_changed', 'remark_added', 'followup_rescheduled',
           'call_initiated', 'whatsapp_sent', 'visit_rescheduled', 'archived'
         )
  ),
  acted_today AS (
    SELECT DISTINCT uid FROM acts WHERE d = local_today
  ),
  days AS (
    SELECT DISTINCT acts.uid, acts.tenant_id, acts.local_today, acts.d
    FROM acts
    WHERE acts.d <= acts.local_today - 1
  ),
  grp AS (
    SELECT days.uid, days.tenant_id, days.local_today, days.d,
           days.d - (row_number() OVER (PARTITION BY days.uid ORDER BY days.d))::int AS island
    FROM days
  ),
  runs AS (
    SELECT grp.uid, grp.tenant_id, grp.local_today,
           max(grp.d) AS run_end, count(*)::int AS run_len
    FROM grp
    GROUP BY grp.uid, grp.tenant_id, grp.local_today, grp.island
  ),
  streaks AS (
    SELECT runs.uid, runs.tenant_id, runs.local_today, runs.run_len AS streak_days
    FROM runs
    WHERE runs.run_end = runs.local_today - 1
      AND runs.run_len >= 3
  )
  SELECT s.uid, s.tenant_id, s.local_today, s.streak_days, dt.token
  FROM streaks s
  JOIN public.device_tokens dt ON dt.user_id = s.uid
  WHERE s.uid NOT IN (SELECT uid FROM acted_today)
    AND NOT EXISTS (
      SELECT 1 FROM public.domain_events de
      WHERE de.event_type = 'notification_sent'
        AND de.payload->>'type' = 'streak_at_risk'
        AND de.payload->>'user_id' = s.uid::text
        AND de.payload->>'local_date' = s.local_today::text
    );
END;
$$;
