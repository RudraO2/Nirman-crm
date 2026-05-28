-- Story 2.7 — mark_lead_dead + restore_lead RPCs
-- mark_lead_dead: sets status='dead', returns {previous_status} for undo.
-- restore_lead:   restores to a given status after undo.
-- Both SECURITY DEFINER; caller ownership verified inside.
-- Roll-forward only. Never edit after apply.

-- ── mark_lead_dead ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.mark_lead_dead(p_lead_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_prev_status text;
BEGIN
  SELECT status::text INTO v_prev_status
    FROM public.leads
   WHERE id                  = p_lead_id
     AND tenant_id           = public.auth_tenant_id()
     AND assigned_to_user_id = auth.uid()
     AND status <> 'dead';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING HINT = 'Lead not found or already dead';
  END IF;

  UPDATE public.leads
     SET status         = 'dead',
         last_action_at = now()
   WHERE id = p_lead_id;

  PERFORM public.log_timeline_event(
    p_lead_id,
    'status_changed',
    jsonb_build_object('from', v_prev_status, 'to', 'dead')
  );

  RETURN jsonb_build_object('previous_status', v_prev_status);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_lead_dead(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mark_lead_dead(uuid) TO   authenticated;

-- ── restore_lead ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.restore_lead(
  p_lead_id        uuid,
  p_restore_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  UPDATE public.leads
     SET status         = p_restore_status::public.lead_status,
         last_action_at = now()
   WHERE id                  = p_lead_id
     AND tenant_id           = public.auth_tenant_id()
     AND assigned_to_user_id = auth.uid()
     AND status              = 'dead';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING HINT = 'Lead not found or not dead';
  END IF;

  PERFORM public.log_timeline_event(
    p_lead_id,
    'status_changed',
    jsonb_build_object('from', 'dead', 'to', p_restore_status, 'restored', true)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.restore_lead(uuid, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.restore_lead(uuid, text) TO   authenticated;
