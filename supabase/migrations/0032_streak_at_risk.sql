-- Story 7.3 — Streak-at-risk push targets + 6 PM (tenant-tz) cron.
-- streak_at_risk_targets(): employees who, right now (their local 18:00), have a
-- >=3-day follow-up streak ending YESTERDAY, no qualifying action TODAY, a device
-- token, and have not yet been notified today. Returns rows for the edge fn to push.
-- Roll-forward only. Never edit after apply.

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
BEGIN
  RETURN QUERY
  WITH due_tenants AS (
    -- Tenants currently in their local 18:00 hour.
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
    SELECT DISTINCT uid, tenant_id, local_today, d
    FROM acts
    WHERE d <= local_today - 1
  ),
  grp AS (
    SELECT uid, tenant_id, local_today, d,
           d - (row_number() OVER (PARTITION BY uid ORDER BY d))::int AS island
    FROM days
  ),
  runs AS (
    SELECT uid, tenant_id, local_today,
           max(d) AS run_end, count(*)::int AS run_len
    FROM grp
    GROUP BY uid, tenant_id, local_today, island
  ),
  streaks AS (
    SELECT uid, tenant_id, local_today, run_len AS streak_days
    FROM runs
    WHERE run_end = local_today - 1   -- live run ends yesterday (today is empty)
      AND run_len >= 3
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

COMMENT ON FUNCTION public.streak_at_risk_targets() IS
  'Story 7.3 — Employees needing a streak-at-risk push right now (local 18:00, >=3-day streak, no action today, not yet notified). SECURITY DEFINER; service_role only.';

REVOKE EXECUTE ON FUNCTION public.streak_at_risk_targets() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.streak_at_risk_targets() TO service_role;

-- ── pg_cron: every 30 min, hit the edge function (self-gates to local 18:00) ──
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'streak-at-risk',
      '0,30 * * * *',
      $job$
        SELECT net.http_post(
          url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1)
                     || '/functions/v1/streak-at-risk',
          headers := jsonb_build_object('Content-Type', 'application/json'),
          body    := '{}'::jsonb
        );
      $job$
    );
  END IF;
END;
$$;
