-- Story 7.1 / FR (Motivation Layer) — get_my_motivation_stats RPC for Employee home stats card.
-- Returns the caller's own: sold-this-month, follow-up streak (days), conversion rate, total assigned.
-- All date bucketing in TENANT timezone (architecture.md: timezone-aware everywhere).
-- Caller-scoped via auth.uid(); no other employee's data is reachable.
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.get_my_motivation_stats()
RETURNS TABLE (
  sold_this_month      int,
  followup_streak_days int,
  conversion_rate      numeric,
  total_assigned       int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id     uuid := auth.uid();
  v_tz          text;
  v_today       date;
  v_month_start timestamp;   -- tenant-local month start (timestamp without tz)
  v_sold        int;
  v_total       int;
  v_streak      int := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Tenant timezone drives all date buckets; default to IST if unset.
  SELECT COALESCE(t.timezone, 'Asia/Kolkata') INTO v_tz
  FROM public.tenants t
  WHERE t.id = auth_tenant_id();
  IF v_tz IS NULL THEN
    v_tz := 'Asia/Kolkata';
  END IF;

  v_today       := (now() AT TIME ZONE v_tz)::date;
  v_month_start := date_trunc('month', now() AT TIME ZONE v_tz);

  -- Total leads ever assigned to caller. Pre-Epic-4 (no reassignment history),
  -- "currently assigned" == "ever assigned".
  SELECT count(*) INTO v_total
  FROM public.leads l
  WHERE l.assigned_to_user_id = v_user_id;

  -- Sold this month: current status sold AND a status_changed->'sold' event this tenant-month.
  -- (Reading (1) per story Dev Notes — avoids counting reverted sales.)
  SELECT count(DISTINCT l.id) INTO v_sold
  FROM public.leads l
  JOIN public.lead_timeline t
    ON t.lead_id    = l.id
   AND t.event_type = 'status_changed'
   AND t.payload->>'to' = 'sold'
   AND (t.occurred_at AT TIME ZONE v_tz) >= v_month_start
  WHERE l.assigned_to_user_id = v_user_id
    AND l.status = 'sold';

  -- Follow-up streak: consecutive tenant-tz calendar days with >=1 qualifying action
  -- by this user, in the run ending today (or yesterday if today has none yet).
  -- Qualifying event_types per Story 3.7.
  WITH active_days AS (
    SELECT DISTINCT (t.occurred_at AT TIME ZONE v_tz)::date AS d
    FROM public.lead_timeline t
    WHERE t.actor_user_id = v_user_id
      AND t.event_type IN (
            'status_changed', 'remark_added', 'followup_rescheduled',
            'call_initiated', 'whatsapp_sent', 'visit_rescheduled', 'archived'
          )
      AND (t.occurred_at AT TIME ZONE v_tz)::date <= v_today
  ),
  grp AS (
    -- Gaps-and-islands: contiguous days share (d - row_number()).
    SELECT d, d - (row_number() OVER (ORDER BY d))::int AS island
    FROM active_days
  ),
  runs AS (
    SELECT max(d) AS run_end, count(*)::int AS run_len
    FROM grp
    GROUP BY island
  )
  SELECT COALESCE(
           (SELECT run_len FROM runs
             WHERE run_end IN (v_today, v_today - 1)
             ORDER BY run_end DESC
             LIMIT 1),
           0)
  INTO v_streak;

  RETURN QUERY
  SELECT
    v_sold,
    v_streak,
    COALESCE(round(100.0 * v_sold / NULLIF(v_total, 0), 1), 0.0)::numeric,
    v_total;
END;
$$;

COMMENT ON FUNCTION public.get_my_motivation_stats() IS
  'Story 7.1 — Caller-scoped motivation stats (sold this month, follow-up streak, conversion rate, total assigned). Tenant-tz date buckets. SECURITY DEFINER.';

REVOKE EXECUTE ON FUNCTION public.get_my_motivation_stats() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_motivation_stats() TO authenticated;
