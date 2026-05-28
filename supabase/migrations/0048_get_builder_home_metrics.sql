-- Story 5.1 — get_builder_home_metrics() RPC for admin home 3-metric dashboard.
-- Returns tenant-wide: leads_today, leads_yesterday, followups_missed_today,
-- followups_missed_yesterday, sold_this_month, sold_last_month.
-- All date bucketing in tenant timezone (public.tenants.timezone).
-- Admin-only; SECURITY DEFINER; search_path = public, extensions.
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.get_builder_home_metrics()
RETURNS TABLE (
  leads_today                 int,
  leads_yesterday             int,
  followups_missed_today      int,
  followups_missed_yesterday  int,
  sold_this_month             int,
  sold_last_month             int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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
  IF (auth.jwt() -> 'app_metadata' ->> 'role') <> 'admin' THEN
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
$$;

COMMENT ON FUNCTION public.get_builder_home_metrics() IS
  'Story 5.1 — Admin home 3-metric dashboard (leads today/yesterday, missed followups today/yesterday, sold this month/last month). Tenant-tz date buckets. Admin-only. SECURITY DEFINER.';

REVOKE EXECUTE ON FUNCTION public.get_builder_home_metrics() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_builder_home_metrics() TO authenticated;
