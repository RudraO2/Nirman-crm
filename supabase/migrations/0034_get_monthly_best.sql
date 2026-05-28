-- Story 7.4 — get_monthly_best RPC for the monthly personal-best card/banner.
-- Caller-scoped; tenant-tz month buckets. Returns this/last month sold counts,
-- all-time best (over months BEFORE the current one), and the tenant-local day of month.
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.get_monthly_best()
RETURNS TABLE (
  this_month_sold int,
  last_month_sold int,
  all_time_best   int,
  day_of_month    int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id     uuid := auth.uid();
  v_tz          text;
  v_this_month  timestamp;
  v_last_month  timestamp;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT COALESCE(t.timezone, 'Asia/Kolkata') INTO v_tz
  FROM public.tenants t WHERE t.id = auth_tenant_id();
  IF v_tz IS NULL THEN v_tz := 'Asia/Kolkata'; END IF;

  v_this_month := date_trunc('month', now() AT TIME ZONE v_tz);
  v_last_month := v_this_month - interval '1 month';

  RETURN QUERY
  WITH sold_leads AS (
    -- One row per sold lead, bucketed to the tenant-local month of its sold event.
    SELECT l.id,
           date_trunc('month', (max(t.occurred_at) AT TIME ZONE v_tz)) AS sold_month
    FROM public.leads l
    JOIN public.lead_timeline t
      ON t.lead_id = l.id
     AND t.event_type = 'status_changed'
     AND t.payload->>'to' = 'sold'
    WHERE l.assigned_to_user_id = v_user_id
      AND l.status = 'sold'
    GROUP BY l.id
  ),
  monthly AS (
    SELECT sold_month, count(*)::int AS c
    FROM sold_leads
    GROUP BY sold_month
  )
  SELECT
    COALESCE((SELECT c FROM monthly WHERE sold_month = v_this_month), 0),
    COALESCE((SELECT c FROM monthly WHERE sold_month = v_last_month), 0),
    COALESCE((SELECT max(c) FROM monthly WHERE sold_month < v_this_month), 0),
    extract(day FROM (now() AT TIME ZONE v_tz))::int;
END;
$$;

COMMENT ON FUNCTION public.get_monthly_best() IS
  'Story 7.4 — Caller-scoped monthly personal-best figures (this/last month sold, all-time best over prior months, tenant-local day of month). SECURITY DEFINER.';

REVOKE EXECUTE ON FUNCTION public.get_monthly_best() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_monthly_best() TO authenticated;
