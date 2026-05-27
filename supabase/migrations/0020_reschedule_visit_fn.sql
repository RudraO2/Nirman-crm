-- Story 2.6 — reschedule_visit RPC
-- Sets new visit_date, increments reschedule_count, logs visit_rescheduled.
-- SECURITY DEFINER: ownership verified inside; no caller-level table access needed.
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.reschedule_visit(
  p_lead_id       uuid,
  p_new_visit_date timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_old_date      timestamptz;
  v_reschedule_cnt integer;
BEGIN
  -- Ownership check: caller must own this lead in this tenant
  SELECT visit_date, reschedule_count
    INTO v_old_date, v_reschedule_cnt
    FROM public.leads
   WHERE id          = p_lead_id
     AND tenant_id   = public.auth_tenant_id()
     AND assigned_to_user_id = auth.uid()
     AND status NOT IN ('dead', 'sold');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING HINT = 'Lead not found in your queue';
  END IF;

  UPDATE public.leads
     SET visit_date       = p_new_visit_date,
         reschedule_count = reschedule_count + 1,
         last_action_at   = now()
   WHERE id = p_lead_id;

  PERFORM public.log_timeline_event(
    p_lead_id,
    'visit_rescheduled',
    jsonb_build_object(
      'from', v_old_date,
      'to',   p_new_visit_date,
      'reschedule_count', v_reschedule_cnt + 1
    )
  );

  RETURN jsonb_build_object(
    'reschedule_count', v_reschedule_cnt + 1,
    'visit_date',       p_new_visit_date
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.reschedule_visit(uuid, timestamptz) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.reschedule_visit(uuid, timestamptz) TO   authenticated;
