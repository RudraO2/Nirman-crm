-- 0081_log_amendment.sql
-- Story 16.2 (Epic 16) — FR-56. Log a client's requested modification against a held/sold unit.
--
-- log_amendment(unit, lead, description): agent (NOT partner_agency) logs an amendment against a unit
-- on hold|sold linked to a lead in the caller's visible_user_ids() scope. Creates the amendment
-- (status 'requested') and DUAL-LOGS: amendment_events (own trail) + lead Timeline (FR-19 reuse, so it
-- shows on the lead card). Notify wiring is 16.4.
--
-- 'amendment_logged' added to timeline_event_type (bare ADD VALUE before BEGIN; used only at call time).
-- File-based migration; never MCP apply.

ALTER TYPE public.timeline_event_type ADD VALUE IF NOT EXISTS 'amendment_logged';

BEGIN;

CREATE OR REPLACE FUNCTION public.log_amendment(
  p_unit_id     uuid,
  p_lead_id     uuid,
  p_description text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_tier      public.role_tier;
  v_status    public.unit_status;
  v_owner     uuid;
  v_amd_id    uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_tier := public.auth_role_tier();
  IF v_tier = 'partner_agency' THEN
    RAISE EXCEPTION 'forbidden_role: partner_agency cannot log amendments' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  IF p_description IS NULL OR length(trim(p_description)) = 0 THEN
    RAISE EXCEPTION 'description_required' USING ERRCODE = 'P0001';
  END IF;

  -- unit must exist in tenant and be amendable (hold or sold)
  SELECT status INTO v_status FROM public.units WHERE id = p_unit_id AND tenant_id = v_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unit_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_status NOT IN ('hold', 'sold') THEN
    RAISE EXCEPTION 'unit_not_amendable: amendments allowed only on hold/sold units (is %)', v_status USING ERRCODE = 'P0001';
  END IF;

  -- lead must be in tenant and within the caller's visibility
  SELECT assigned_to_user_id INTO v_owner FROM public.leads WHERE id = p_lead_id AND tenant_id = v_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'lead_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.visible_user_ids() v WHERE v.user_id = v_owner) THEN
    RAISE EXCEPTION 'lead_not_visible' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.amendments (tenant_id, unit_id, lead_id, description, status, logged_by)
  VALUES (v_tenant_id, p_unit_id, p_lead_id, p_description, 'requested', auth.uid())
  RETURNING id INTO v_amd_id;

  -- dual-log: amendment trail + lead timeline (FR-19 reuse)
  PERFORM public.log_amendment_event(v_amd_id, 'logged', NULL, 'requested'::public.amendment_status, p_description);
  PERFORM public.log_timeline_event(
    p_lead_id, 'amendment_logged'::public.timeline_event_type,
    jsonb_build_object('amendment_id', v_amd_id, 'unit_id', p_unit_id, 'description', p_description)
  );

  RETURN v_amd_id;
END;
$$;

REVOKE ALL ON FUNCTION public.log_amendment(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.log_amendment(uuid, uuid, text) TO authenticated;

COMMENT ON FUNCTION public.log_amendment(uuid, uuid, text) IS
  'Story 16.2 — agent (not partner_agency) logs an amendment on a hold/sold unit for a visible lead. Creates requested amendment + dual-logs (amendment_events + lead timeline). Returns amendment id.';

COMMIT;
