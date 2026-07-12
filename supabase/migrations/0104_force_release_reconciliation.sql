-- 0104_force_release_reconciliation.sql
-- Robustness-audit 2026-07-11 MEDIUM: change_unit_inventory_state('force_release') reverted a SOLD
-- unit to available without reconciling the lead — the lead stayed 'sold' (with its unit_booked
-- timeline entry) while the unit went back into the pool, so a second hold->confirm on the same
-- physical unit produced TWO 'sold' leads for one unit (latent double-sale). The active-hold half
-- of the finding was already fixed by 0084 FIX 1 (outcome='cancelled'); this closes the lead half.
--
-- Changes to force_release (same signature, roll-forward):
--   • sold unit: locate the most recent converted hold for the unit; if its lead is still 'sold',
--     revert it to 'hot' (back into the pipeline at closing stage) via the shipped status-change
--     seam (status_changed timeline, payload carries reason='force_release'), and log a
--     'booking_reverted' timeline entry {unit_id, hold_id}. A sold unit with no converted hold
--     (legacy/direct data) skips the lead revert — nothing to reconcile.
--   • held unit: the 0084 hold-cancel now ALSO logs a 'hold_cancelled' timeline entry on the
--     hold's lead — previously the head override was invisible to the holding agent.
--
-- 'booking_reverted' / 'hold_cancelled' added to timeline_event_type (bare ADD VALUE before BEGIN,
-- used only at call time — the 0078 pattern). Unknown types render via the clients' default case.
-- File-based migration; never MCP apply.

ALTER TYPE public.timeline_event_type ADD VALUE IF NOT EXISTS 'booking_reverted';
ALTER TYPE public.timeline_event_type ADD VALUE IF NOT EXISTS 'hold_cancelled';

BEGIN;

CREATE OR REPLACE FUNCTION public.change_unit_inventory_state(
  p_unit_id          uuid,
  p_action           text,
  p_expected_version int DEFAULT NULL
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id    uuid;
  v_status       public.unit_status;
  v_version      int;
  v_new          public.unit_status;
  v_hold_id      uuid;
  v_hold_lead_id uuid;
  v_lead_status  text;
BEGIN
  IF public.auth_role_tier() IS DISTINCT FROM 'builder_head' THEN
    RAISE EXCEPTION 'permission_denied: builder_head only' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  SELECT status, status_version INTO v_status, v_version
  FROM public.units WHERE id = p_unit_id AND tenant_id = v_tenant_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unit_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF p_expected_version IS NOT NULL AND p_expected_version <> v_version THEN
    RAISE EXCEPTION 'unit_version_conflict: expected % but is %', p_expected_version, v_version USING ERRCODE = 'P0001';
  END IF;

  IF p_action = 'withdraw' THEN
    IF v_status IN ('hold', 'sold') THEN
      RAISE EXCEPTION 'unit_locked_release_first: cannot withdraw a % unit — release it first', v_status USING ERRCODE = 'P0001';
    END IF;
    IF v_status <> 'available' THEN
      RAISE EXCEPTION 'invalid_transition: % -> blocked', v_status USING ERRCODE = 'P0001';
    END IF;
    v_new := 'blocked';
  ELSIF p_action = 'restock' THEN
    IF v_status <> 'blocked' THEN
      RAISE EXCEPTION 'invalid_transition: % -> available (restock)', v_status USING ERRCODE = 'P0001';
    END IF;
    v_new := 'available';
  ELSIF p_action = 'force_release' THEN
    IF v_status NOT IN ('hold', 'sold') THEN
      RAISE EXCEPTION 'invalid_transition: % -> available (force_release)', v_status USING ERRCODE = 'P0001';
    END IF;
    v_new := 'available';
  ELSE
    RAISE EXCEPTION 'invalid_action: %', p_action USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.units
     SET status = v_new, status_version = status_version + 1
   WHERE id = p_unit_id AND tenant_id = v_tenant_id
   RETURNING status_version INTO v_version;

  IF p_action = 'force_release' THEN
    IF v_status = 'hold' THEN
      -- 0084 FIX 1: close the active hold; now also make the override visible on the lead timeline.
      UPDATE public.unit_holds
         SET released_at = now(), outcome = 'cancelled'
       WHERE unit_id = p_unit_id AND released_at IS NULL
       RETURNING id, lead_id INTO v_hold_id, v_hold_lead_id;
      IF v_hold_lead_id IS NOT NULL THEN
        PERFORM public.log_timeline_event(
          v_hold_lead_id, 'hold_cancelled'::public.timeline_event_type,
          jsonb_build_object('unit_id', p_unit_id, 'hold_id', v_hold_id, 'reason', 'force_release')
        );
      END IF;

    ELSIF v_status = 'sold' THEN
      -- Reconcile the booking's lead: the unit re-enters the pool, so the lead must not stay
      -- 'sold' (two 'sold' leads on one unit after resale = the double-sale the audit flagged).
      SELECT id, lead_id INTO v_hold_id, v_hold_lead_id
      FROM public.unit_holds
      WHERE unit_id = p_unit_id AND tenant_id = v_tenant_id AND outcome = 'converted'
      ORDER BY released_at DESC
      LIMIT 1;

      IF v_hold_lead_id IS NOT NULL THEN
        SELECT status::text INTO v_lead_status
        FROM public.leads WHERE id = v_hold_lead_id AND tenant_id = v_tenant_id
        FOR UPDATE;

        IF v_lead_status = 'sold' THEN
          UPDATE public.leads SET status = 'hot', last_action_at = now()
           WHERE id = v_hold_lead_id AND tenant_id = v_tenant_id;
          PERFORM public.log_timeline_event(
            v_hold_lead_id, 'status_changed',
            jsonb_build_object('from', 'sold', 'to', 'hot', 'reason', 'force_release')
          );
        END IF;

        PERFORM public.log_timeline_event(
          v_hold_lead_id, 'booking_reverted'::public.timeline_event_type,
          jsonb_build_object('unit_id', p_unit_id, 'hold_id', v_hold_id)
        );
      END IF;
    END IF;
  END IF;

  IF v_new = 'available' THEN
    PERFORM public.emit_inventory_changed(
      p_unit_id,
      CASE WHEN p_action = 'restock' THEN 'new_stock' ELSE 'release' END
    );
  END IF;

  RETURN v_version;
END;
$$;

REVOKE ALL ON FUNCTION public.change_unit_inventory_state(uuid, text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.change_unit_inventory_state(uuid, text, int) TO authenticated;

COMMENT ON FUNCTION public.change_unit_inventory_state(uuid, text, int) IS
  'Story 14.5 + audit-0104 — builder_head inventory transitions: withdraw, restock, force_release. force_release reconciles: held unit -> cancels the active hold + hold_cancelled timeline; sold unit -> reverts the booked lead sold->hot (status_changed seam) + booking_reverted timeline. CAS on status_version; emits inventory_changed on ->available.';

COMMIT;
