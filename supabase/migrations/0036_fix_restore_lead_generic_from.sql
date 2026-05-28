-- Story 2.8 fix — restore_lead (0021) had two bugs that blocked restoring sold/future leads:
--   1) WHERE status = 'dead' restricted restores to the dead status only.
--   2) Timeline 'from' field was hardcoded to 'dead'.
-- Generalise so restore works from any archived status (dead/sold/future) and logs the actual prior status.
-- Signature unchanged.  Roll-forward only.

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
  -- Caller must own the lead and it must currently be archived.
  SELECT l.status::text INTO v_prev
  FROM public.leads l
  WHERE l.id                  = p_lead_id
    AND l.tenant_id           = public.auth_tenant_id()
    AND l.assigned_to_user_id = auth.uid()
    AND l.status              IN ('dead','sold','future');

  IF v_prev IS NULL THEN
    RAISE EXCEPTION 'not_found' USING HINT = 'Lead not found or not archived';
  END IF;

  UPDATE public.leads
     SET status         = p_restore_status::public.lead_status,
         last_action_at = now()
   WHERE id = p_lead_id;

  PERFORM public.log_timeline_event(
    p_lead_id,
    'status_changed',
    jsonb_build_object('from', v_prev, 'to', p_restore_status, 'restored', true)
  );
END;
$$;
