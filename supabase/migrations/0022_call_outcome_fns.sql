-- Story 3.1 + 3.2 — Click-to-Call and Pending Outcome RPCs
-- initiate_call:       sets pending_outcome_at, logs call_initiated.
-- submit_call_outcome: updates status/remarks/followup, clears pending_outcome_at.
-- clear_pending_outcome: clears pending_outcome_at, logs call_outcome_cleared.
-- All SECURITY DEFINER; caller ownership verified inside.
-- Roll-forward only. Never edit after apply.

-- ── initiate_call ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.initiate_call(p_lead_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  UPDATE public.leads
     SET pending_outcome_at = now(),
         last_action_at     = now()
   WHERE id                  = p_lead_id
     AND tenant_id           = public.auth_tenant_id()
     AND assigned_to_user_id = auth.uid()
     AND status NOT IN ('dead', 'sold');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING HINT = 'Lead not found in your queue';
  END IF;

  PERFORM public.log_timeline_event(
    p_lead_id,
    'call_initiated',
    '{}'::jsonb
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.initiate_call(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.initiate_call(uuid) TO   authenticated;

-- ── submit_call_outcome ───────────────────────────────────────────────────────
-- p_remarks: new remark text to append (NULL = skip remark event)
-- p_followup_at: new follow-up timestamp (NULL = no follow-up change)

CREATE OR REPLACE FUNCTION public.submit_call_outcome(
  p_lead_id    uuid,
  p_new_status text,
  p_remarks    text        DEFAULT NULL,
  p_followup_at timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_old_status text;
  v_old_followup timestamptz;
BEGIN
  SELECT status::text, next_followup_at
    INTO v_old_status, v_old_followup
    FROM public.leads
   WHERE id                  = p_lead_id
     AND tenant_id           = public.auth_tenant_id()
     AND assigned_to_user_id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING HINT = 'Lead not found in your queue';
  END IF;

  UPDATE public.leads
     SET status             = p_new_status::public.lead_status,
         pending_outcome_at = NULL,
         last_action_at     = now(),
         remarks            = CASE
                                WHEN p_remarks IS NOT NULL
                                THEN COALESCE(remarks || E'\n', '') || p_remarks
                                ELSE remarks
                              END,
         next_followup_at   = COALESCE(p_followup_at, next_followup_at)
   WHERE id = p_lead_id;

  -- Always log status change
  PERFORM public.log_timeline_event(
    p_lead_id,
    'status_changed',
    jsonb_build_object('from', v_old_status, 'to', p_new_status)
  );

  -- Remark event only when a remark was provided
  IF p_remarks IS NOT NULL THEN
    PERFORM public.log_timeline_event(
      p_lead_id,
      'remark_added',
      '{}'::jsonb
    );
  END IF;

  -- Follow-up event only when a date was provided
  IF p_followup_at IS NOT NULL THEN
    PERFORM public.log_timeline_event(
      p_lead_id,
      CASE WHEN v_old_followup IS NOT NULL THEN 'followup_rescheduled' ELSE 'followup_set' END::public.timeline_event_type,
      CASE WHEN v_old_followup IS NOT NULL
           THEN jsonb_build_object('from', v_old_followup, 'to', p_followup_at)
           ELSE jsonb_build_object('at', p_followup_at)
      END
    );
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.submit_call_outcome(uuid, text, text, timestamptz) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.submit_call_outcome(uuid, text, text, timestamptz) TO   authenticated;

-- ── clear_pending_outcome ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.clear_pending_outcome(p_lead_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  UPDATE public.leads
     SET pending_outcome_at = NULL,
         last_action_at     = now()
   WHERE id                  = p_lead_id
     AND tenant_id           = public.auth_tenant_id()
     AND assigned_to_user_id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING HINT = 'Lead not found in your queue';
  END IF;

  PERFORM public.log_timeline_event(
    p_lead_id,
    'call_outcome_cleared',
    '{}'::jsonb
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.clear_pending_outcome(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.clear_pending_outcome(uuid) TO   authenticated;
