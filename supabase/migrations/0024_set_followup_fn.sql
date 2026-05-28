-- Story 3.5 — set_followup RPC
-- Sets next_followup_at; logs followup_set or followup_rescheduled.
-- SECURITY DEFINER; ownership verified inside.
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.set_followup(
  p_lead_id uuid,
  p_at      timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_old_followup timestamptz;
BEGIN
  SELECT next_followup_at
    INTO v_old_followup
    FROM public.leads
   WHERE id                  = p_lead_id
     AND tenant_id           = public.auth_tenant_id()
     AND assigned_to_user_id = auth.uid()
     AND status NOT IN ('dead', 'sold');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING HINT = 'Lead not found in your queue';
  END IF;

  UPDATE public.leads
     SET next_followup_at = p_at,
         last_action_at   = now()
   WHERE id = p_lead_id;

  PERFORM public.log_timeline_event(
    p_lead_id,
    CASE WHEN v_old_followup IS NOT NULL
         THEN 'followup_rescheduled'
         ELSE 'followup_set'
    END::public.timeline_event_type,
    CASE WHEN v_old_followup IS NOT NULL
         THEN jsonb_build_object('from', v_old_followup, 'to', p_at)
         ELSE jsonb_build_object('at', p_at)
    END
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_followup(uuid, timestamptz) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_followup(uuid, timestamptz) TO   authenticated;
