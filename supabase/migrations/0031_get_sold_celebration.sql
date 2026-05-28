-- Story 7.2 — get_sold_celebration RPC for the Sold celebration earned-moment card.
-- Caller-scoped (auth.uid()); returns the earned-moment numbers for one owned, sold lead.
-- Tenant-tz buckets for month/quarter. The personal-record LINE is composed client-side.
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.get_sold_celebration(p_lead_id uuid)
RETURNS TABLE (
  days_to_close       int,
  action_count        int,
  sold_this_month     int,
  is_fastest_quarter  boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id      uuid := auth.uid();
  v_tz           text;
  v_created_at   timestamptz;
  v_sold_at      timestamptz;
  v_days         int;
  v_actions      int;
  v_month        int;
  v_min_quarter  int;
  v_month_start  timestamp;
  v_quarter_start timestamp;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Ownership + sold gate — return 0 rows if not the caller's sold lead.
  SELECT l.created_at INTO v_created_at
  FROM public.leads l
  WHERE l.id = p_lead_id
    AND l.assigned_to_user_id = v_user_id
    AND l.status = 'sold';
  IF v_created_at IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(t.timezone, 'Asia/Kolkata') INTO v_tz
  FROM public.tenants t WHERE t.id = auth_tenant_id();
  IF v_tz IS NULL THEN v_tz := 'Asia/Kolkata'; END IF;

  v_month_start   := date_trunc('month',   now() AT TIME ZONE v_tz);
  v_quarter_start := date_trunc('quarter', now() AT TIME ZONE v_tz);

  -- The sold moment for this lead (latest status_changed -> sold).
  SELECT max(t.occurred_at) INTO v_sold_at
  FROM public.lead_timeline t
  WHERE t.lead_id = p_lead_id
    AND t.event_type = 'status_changed'
    AND t.payload->>'to' = 'sold';

  v_days := GREATEST(0, floor(extract(epoch FROM COALESCE(v_sold_at, now()) - v_created_at) / 86400.0)::int);

  SELECT count(*)::int INTO v_actions
  FROM public.lead_timeline t
  WHERE t.lead_id = p_lead_id
    AND t.event_type IN ('call_initiated', 'whatsapp_sent', 'followup_completed');

  -- Caller's sold-this-month count (current status sold + a sold event this tenant-month).
  SELECT count(DISTINCT l.id)::int INTO v_month
  FROM public.leads l
  JOIN public.lead_timeline t
    ON t.lead_id = l.id
   AND t.event_type = 'status_changed'
   AND t.payload->>'to' = 'sold'
   AND (t.occurred_at AT TIME ZONE v_tz) >= v_month_start
  WHERE l.assigned_to_user_id = v_user_id
    AND l.status = 'sold';

  -- Minimum days-to-close among the caller's closes this tenant-quarter.
  SELECT min(GREATEST(0, floor(extract(epoch FROM closed.sold_at - l.created_at) / 86400.0)::int))
    INTO v_min_quarter
  FROM public.leads l
  JOIN LATERAL (
    SELECT max(t.occurred_at) AS sold_at
    FROM public.lead_timeline t
    WHERE t.lead_id = l.id
      AND t.event_type = 'status_changed'
      AND t.payload->>'to' = 'sold'
  ) closed ON true
  WHERE l.assigned_to_user_id = v_user_id
    AND l.status = 'sold'
    AND closed.sold_at IS NOT NULL
    AND (closed.sold_at AT TIME ZONE v_tz) >= v_quarter_start;

  RETURN QUERY SELECT
    v_days,
    v_actions,
    v_month,
    (v_min_quarter IS NOT NULL AND v_days <= v_min_quarter);
END;
$$;

COMMENT ON FUNCTION public.get_sold_celebration(uuid) IS
  'Story 7.2 — Earned-moment numbers for one owned, sold lead (days to close, action count, sold-this-month, fastest-this-quarter). SECURITY DEFINER; caller-scoped.';

REVOKE EXECUTE ON FUNCTION public.get_sold_celebration(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_sold_celebration(uuid) TO authenticated;
