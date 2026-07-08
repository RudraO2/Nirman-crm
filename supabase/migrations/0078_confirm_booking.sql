-- 0078_confirm_booking.sql
-- Story 15.4 (Epic 15) — FR-54. Confirm a hold as a booking on payment verification.
--
-- confirm_booking(p_hold_id, p_payment_verified) — builder_head | team_leader only (leaders CAN
-- confirm; margin stays head-only elsewhere). One transaction:
--   hold  → released_at=now(), outcome='converted'   (enum hold_outcome value = AC's "confirmed")
--   unit  → 'sold', status_version+1
--   lead  → 'sold' via the SHIPPED status-change seam: UPDATE + log_timeline_event('status_changed',
--           {from,to:'sold'}) — this is exactly what the FR-34 mobile Sold-celebration listens on, so
--           the celebration fires with NO new code (status_changed→sold timeline + domain_event).
--   + log_timeline_event('unit_booked', {unit_id, hold_id}).
-- Confirming clears the hold (released) so the 15.3 cron skips it.
--
-- Revert guard (AC5): sold→available is head-only via change_unit_inventory_state('force_release')
-- (0074) which is already builder_head-gated + emits inventory_changed (logged). Non-head cannot
-- revert. A full booking-revert that also reverts the lead is a head-only follow-on.
--
-- 'unit_booked' added to timeline_event_type (bare ADD VALUE before BEGIN; used only at call time).
-- File-based migration; never MCP apply.

ALTER TYPE public.timeline_event_type ADD VALUE IF NOT EXISTS 'unit_booked';

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

  SELECT unit_id, lead_id, released_at INTO v_unit_id, v_lead_id, v_released
  FROM public.unit_holds
  WHERE id = p_hold_id AND tenant_id = v_tenant_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'hold_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_released IS NOT NULL THEN
    RAISE EXCEPTION 'hold_not_active: hold already released/expired/converted' USING ERRCODE = 'P0001';
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

REVOKE ALL ON FUNCTION public.confirm_booking(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_booking(uuid, boolean) TO authenticated;

COMMENT ON FUNCTION public.confirm_booking(uuid, boolean) IS
  'Story 15.4 — builder_head/team_leader confirm a hold (payment_verified required). One txn: hold→converted, unit→sold, lead→sold via status_changed seam (fires FR-34 celebration) + unit_booked. Returns booking summary.';

COMMIT;
