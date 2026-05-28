-- Code-review patches (2026-05-28) — covers P3, P4, P5, P7, P9, P11.
-- Roll-forward only. Never edit after apply.

-- ── P5: get_sold_celebration — exclude self from v_min_quarter, use strict < ──
-- Old code put the current lead in the set being minimised, so v_days <= v_min_quarter
-- was tautologically true on the FIRST sale of every quarter. Exclude self, then use
-- strict `<` for genuine improvements; result is also gated on the set being non-empty
-- after the exclusion (else "fastest" is meaningless).
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
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT l.created_at INTO v_created_at
  FROM public.leads l
  WHERE l.id = p_lead_id
    AND l.assigned_to_user_id = v_user_id
    AND l.status = 'sold';
  IF v_created_at IS NULL THEN RETURN; END IF;

  SELECT COALESCE(t.timezone, 'Asia/Kolkata') INTO v_tz
  FROM public.tenants t WHERE t.id = auth_tenant_id();
  IF v_tz IS NULL THEN v_tz := 'Asia/Kolkata'; END IF;

  v_month_start   := date_trunc('month',   now() AT TIME ZONE v_tz);
  v_quarter_start := date_trunc('quarter', now() AT TIME ZONE v_tz);

  SELECT max(t.occurred_at) INTO v_sold_at
  FROM public.lead_timeline t
  WHERE t.lead_id = p_lead_id
    AND t.event_type = 'status_changed'
    AND t.payload->>'to' = 'sold';

  v_days := GREATEST(0, floor(extract(epoch FROM COALESCE(v_sold_at, now()) - v_created_at) / 86400.0)::int);

  SELECT count(*)::int INTO v_actions
  FROM public.lead_timeline t
  WHERE t.lead_id = p_lead_id
    AND t.event_type IN ('call_initiated','whatsapp_sent','followup_completed');

  SELECT count(DISTINCT l.id)::int INTO v_month
  FROM public.leads l
  JOIN public.lead_timeline t
    ON t.lead_id = l.id
   AND t.event_type = 'status_changed'
   AND t.payload->>'to' = 'sold'
   AND (t.occurred_at AT TIME ZONE v_tz) >= v_month_start
  WHERE l.assigned_to_user_id = v_user_id
    AND l.status = 'sold';

  -- Min days-to-close among caller's OTHER closes this quarter (exclude self).
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
    AND l.id <> p_lead_id
    AND closed.sold_at IS NOT NULL
    AND (closed.sold_at AT TIME ZONE v_tz) >= v_quarter_start;

  RETURN QUERY SELECT
    v_days,
    v_actions,
    v_month,
    (v_min_quarter IS NOT NULL AND v_days < v_min_quarter);  -- strict; first sale of quarter no longer auto-qualifies
END;
$$;

-- ── P7: get_monthly_best — return tenant-tz month_key so client doesn't rely on device tz ──
-- Adding a column to RETURNS TABLE changes the return type → must DROP first (CREATE OR REPLACE refuses).
DROP FUNCTION IF EXISTS public.get_monthly_best();
CREATE FUNCTION public.get_monthly_best()
RETURNS TABLE (
  this_month_sold int,
  last_month_sold int,
  all_time_best   int,
  day_of_month    int,
  month_key       text   -- YYYY-MM in tenant tz; used for dismissal persistence
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
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT COALESCE(t.timezone, 'Asia/Kolkata') INTO v_tz
  FROM public.tenants t WHERE t.id = auth_tenant_id();
  IF v_tz IS NULL THEN v_tz := 'Asia/Kolkata'; END IF;

  v_this_month := date_trunc('month', now() AT TIME ZONE v_tz);
  v_last_month := v_this_month - interval '1 month';

  RETURN QUERY
  WITH sold_leads AS (
    SELECT l.id,
           date_trunc('month', (max(t.occurred_at) AT TIME ZONE v_tz)) AS sold_month
    FROM public.leads l
    JOIN public.lead_timeline t
      ON t.lead_id = l.id
     AND t.event_type = 'status_changed'
     AND t.payload->>'to' = 'sold'
    WHERE l.assigned_to_user_id = v_user_id AND l.status = 'sold'
    GROUP BY l.id
  ),
  monthly AS (
    SELECT sold_month, count(*)::int AS c FROM sold_leads GROUP BY sold_month
  )
  SELECT
    COALESCE((SELECT c FROM monthly WHERE sold_month = v_this_month), 0),
    COALESCE((SELECT c FROM monthly WHERE sold_month = v_last_month), 0),
    COALESCE((SELECT max(c) FROM monthly WHERE sold_month < v_this_month), 0),
    extract(day FROM (now() AT TIME ZONE v_tz))::int,
    to_char((now() AT TIME ZONE v_tz)::date, 'YYYY-MM');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_monthly_best() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_monthly_best() TO authenticated;

-- ── P9: restore_lead — re-gate UPDATE on tenant+owner+archived (SELECT-UPDATE race);
--      idempotent for already-restored leads (P6's "user retry after server commit") ──
CREATE OR REPLACE FUNCTION public.restore_lead(
  p_lead_id        uuid,
  p_restore_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_prev text;
BEGIN
  SELECT l.status::text INTO v_prev
  FROM public.leads l
  WHERE l.id                  = p_lead_id
    AND l.tenant_id           = public.auth_tenant_id()
    AND l.assigned_to_user_id = auth.uid();

  IF v_prev IS NULL THEN
    RAISE EXCEPTION 'not_found' USING HINT = 'Lead not found or not yours';
  END IF;

  -- Idempotent: if already in an active status, no-op success.
  IF v_prev NOT IN ('dead', 'sold', 'future') THEN
    RETURN;
  END IF;

  UPDATE public.leads
     SET status         = p_restore_status::public.lead_status,
         last_action_at = now()
   WHERE id                  = p_lead_id
     AND tenant_id           = public.auth_tenant_id()
     AND assigned_to_user_id = auth.uid()
     AND status              IN ('dead', 'sold', 'future');

  PERFORM public.log_timeline_event(
    p_lead_id,
    'status_changed',
    jsonb_build_object('from', v_prev, 'to', p_restore_status, 'restored', true)
  );
END;
$$;

-- ── P4: streak-at-risk dedup race — partial unique index ──
-- Guarantees one notification_sent row per (user_id, local_date) for streak_at_risk type,
-- so even if the edge fn races itself the INSERT … ON CONFLICT DO NOTHING is safe.
CREATE UNIQUE INDEX IF NOT EXISTS domain_events_streak_at_risk_dedup_idx
  ON public.domain_events ((payload->>'user_id'), (payload->>'local_date'))
  WHERE event_type = 'notification_sent'
    AND payload->>'type' = 'streak_at_risk';

-- ── P3 + P11: get_my_archived_leads — escape ILIKE wildcards, return last-4 phone,
--      keep PII decrypt necessary for name search but skip phone decrypt entirely ──
CREATE OR REPLACE FUNCTION public.get_my_archived_leads(
  p_q      text  DEFAULT NULL,
  p_limit  int   DEFAULT 50,
  p_offset int   DEFAULT 0
)
RETURNS TABLE (
  id                 uuid,
  status             text,
  name               text,
  phone              text,            -- last 4 digits only (per spec AC-3)
  source             text,
  property_type      text,
  location           text,
  budget_min         bigint,
  budget_max         bigint,
  ticket_size        text,
  visit_date         timestamptz,
  next_followup_at   timestamptz,
  is_incomplete      boolean,
  pending_outcome_at timestamptz,
  last_action_at     timestamptz,
  created_at         timestamptz,
  urgency_score      int,
  archived_at        timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
  v_user_id    uuid := auth.uid();
  v_pii_key    text;
  v_q          text;
  v_q_escaped  text;
  v_phone      text;
  v_phone_hash text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT s.decrypted_secret INTO v_pii_key
  FROM vault.decrypted_secrets s
  WHERE s.name = 'lead_pii_key' LIMIT 1;
  IF v_pii_key IS NULL THEN RAISE EXCEPTION 'pii_key_missing'; END IF;

  v_q := NULLIF(trim(COALESCE(p_q, '')), '');
  IF v_q IS NOT NULL THEN
    -- Escape ILIKE meta-characters so a literal `%` from the user does not match all rows.
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
      l.status::text AS status,
      l.name_encrypted,
      l.phone_encrypted,
      l.source::text AS source,
      l.property_type,
      l.location,
      l.budget_min,
      l.budget_max,
      l.ticket_size,
      l.visit_date,
      l.next_followup_at,
      l.is_incomplete,
      l.pending_outcome_at,
      l.last_action_at,
      l.created_at,
      l.phone_hash,
      (SELECT max(t.occurred_at)
         FROM public.lead_timeline t
        WHERE t.lead_id = l.id
          AND t.event_type = 'status_changed'
          AND t.payload->>'to' IN ('dead','sold','future')) AS archived_at
    FROM public.leads l
    WHERE l.assigned_to_user_id = v_user_id
      AND l.status IN ('dead','sold','future')
  ),
  -- For phone search, restrict cheaply via phone_hash; for name search, decrypt + ILIKE.
  filtered AS (
    SELECT * FROM base
     WHERE v_q IS NULL
        OR (v_phone_hash IS NOT NULL AND phone_hash = v_phone_hash)
        OR (v_q_escaped IS NOT NULL AND name_encrypted IS NOT NULL
            AND extensions.pgp_sym_decrypt(name_encrypted, v_pii_key)
                  ILIKE '%' || v_q_escaped || '%' ESCAPE '\')
  )
  SELECT
    f.id,
    f.status,
    CASE WHEN f.name_encrypted IS NOT NULL
         THEN extensions.pgp_sym_decrypt(f.name_encrypted, v_pii_key)
         ELSE NULL END AS name,
    right(extensions.pgp_sym_decrypt(f.phone_encrypted, v_pii_key), 4) AS phone,
    f.source, f.property_type, f.location,
    f.budget_min, f.budget_max, f.ticket_size,
    f.visit_date, f.next_followup_at,
    f.is_incomplete, f.pending_outcome_at, f.last_action_at, f.created_at,
    0::int AS urgency_score,
    f.archived_at
  FROM filtered f
  ORDER BY f.archived_at DESC NULLS LAST, f.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;
