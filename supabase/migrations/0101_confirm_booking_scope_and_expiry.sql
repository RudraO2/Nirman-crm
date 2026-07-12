-- 0101_confirm_booking_scope_and_expiry.sql
-- Robustness audit 2026-07-11, findings H5 (HIGH) + medium (lapsed-hold confirm).
--
-- Two gaps in confirm_booking (0078):
--   1. H5 — a team_leader could confirm ANY hold in the tenant, including one
--      entirely outside their reporting line, misattributing another team's
--      sale. Now: a team_leader may only confirm a hold whose holding agent
--      is inside their visibility set (visible_user_ids(), the same 12.5
--      primitive get_team_leads uses). builder_head stays tenant-wide.
--   2. A hold past expires_at but not yet swept by the once-a-minute 15.3
--      cron could still be confirmed. Now rejected as hold_not_active.
--
-- Everything else is byte-identical to 0078 (payment gate, hold→converted,
-- unit→sold CAS, lead→sold via the status_changed seam, unit_booked event).

BEGIN;

CREATE OR REPLACE FUNCTION public.confirm_booking(
  p_hold_id          uuid,
  p_payment_verified boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_tier      public.role_tier;
  v_unit_id   uuid;
  v_lead_id   uuid;
  v_agent_id  uuid;
  v_expires   timestamptz;
  v_released  timestamptz;
  v_prev      text;
BEGIN
  v_tier := public.auth_role_tier();
  IF v_tier IS DISTINCT FROM 'builder_head' AND v_tier IS DISTINCT FROM 'team_leader' THEN
    RAISE EXCEPTION 'forbidden_role: only builder_head or team_leader may confirm a booking' USING ERRCODE = '42501';
  END IF;

  IF p_payment_verified IS NOT TRUE THEN
    RAISE EXCEPTION 'payment_not_verified: confirmation requires verified payment' USING ERRCODE = 'P0001';
  END IF;

  v_tenant_id := public.auth_tenant_id();

  SELECT unit_id, lead_id, holding_agent_id, expires_at, released_at
    INTO v_unit_id, v_lead_id, v_agent_id, v_expires, v_released
  FROM public.unit_holds
  WHERE id = p_hold_id AND tenant_id = v_tenant_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'hold_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_released IS NOT NULL THEN
    RAISE EXCEPTION 'hold_not_active: hold already released/expired/converted' USING ERRCODE = 'P0001';
  END IF;
  -- Audit 0101: a lapsed hold awaiting the sweep cron is NOT confirmable.
  IF v_expires <= now() THEN
    RAISE EXCEPTION 'hold_not_active: hold has expired' USING ERRCODE = 'P0001';
  END IF;

  -- Audit H5 (0101): a team_leader may only confirm holds held inside their
  -- reporting subtree (self included). builder_head remains tenant-wide.
  IF v_tier = 'team_leader'
     AND v_agent_id NOT IN (SELECT user_id FROM public.visible_user_ids()) THEN
    RAISE EXCEPTION 'forbidden_scope: hold belongs to an agent outside your team' USING ERRCODE = '42501';
  END IF;

  -- hold → converted
  UPDATE public.unit_holds
     SET released_at = now(), outcome = 'converted'
   WHERE id = p_hold_id;

  -- unit → sold (must currently be on hold)
  UPDATE public.units
     SET status = 'sold', status_version = status_version + 1
   WHERE id = v_unit_id AND tenant_id = v_tenant_id AND status = 'hold';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unit_not_held: unit is not in hold state' USING ERRCODE = 'P0001';
  END IF;

  -- lead → sold via the shipped status-change seam (fires FR-34 celebration)
  SELECT status::text INTO v_prev FROM public.leads WHERE id = v_lead_id AND tenant_id = v_tenant_id;
  UPDATE public.leads SET status = 'sold', last_action_at = now()
   WHERE id = v_lead_id AND tenant_id = v_tenant_id;
  PERFORM public.log_timeline_event(
    v_lead_id, 'status_changed',
    jsonb_build_object('from', v_prev, 'to', 'sold')
  );

  PERFORM public.log_timeline_event(
    v_lead_id, 'unit_booked'::public.timeline_event_type,
    jsonb_build_object('unit_id', v_unit_id, 'hold_id', p_hold_id)
  );

  RETURN jsonb_build_object('hold_id', p_hold_id, 'unit_id', v_unit_id, 'lead_id', v_lead_id, 'status', 'sold');
END;
$$;

COMMENT ON FUNCTION public.confirm_booking(uuid, boolean) IS
  'Story 15.4 + 0101 (audit H5) — builder_head/team_leader confirm a hold (payment_verified required; team_leader limited to holds inside visible_user_ids(); expired holds rejected). One txn: hold→converted, unit→sold, lead→sold via status_changed seam (fires FR-34 celebration) + unit_booked. Returns booking summary.';

COMMIT;
