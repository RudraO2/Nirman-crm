-- 0084_hardening_fixes.sql
-- Hardening fixes found by adversarial backend review (2026-06-28). Roll-forward; same signatures.
--
-- FIX 1 (correctness — orphan hold): change_unit_inventory_state('force_release') of a HELD unit
--   flipped the unit to available but left the unit_holds row ACTIVE (released_at IS NULL). The unit
--   then looked available but could not be re-held (partial-unique still occupied → unit_unavailable).
--   Now force_release also releases the active hold (outcome='cancelled').
-- FIX 2 (sandbox — partner scope): hold_unit let a partner_agency hold a unit in a project NOT shared
--   to their agency. Now partners may hold only within agency-shared projects (project_not_shared).
-- FIX 3 (integrity — amendment link): log_amendment let an amendment be filed for a lead not linked to
--   the unit. Now the lead must have an active hold OR a confirmed booking on that unit
--   (lead_not_linked_to_unit).
--
-- File-based migration; never MCP apply.

BEGIN;

-- ── FIX 1: change_unit_inventory_state — release the hold row on force_release ──────────────
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
  v_tenant_id uuid;
  v_status    public.unit_status;
  v_version   int;
  v_new       public.unit_status;
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

  -- FIX 1: force_release must also close any active hold on the unit, else it orphans
  -- (unit available but the partial-unique keeps it unholdable).
  IF p_action = 'force_release' THEN
    UPDATE public.unit_holds
       SET released_at = now(), outcome = 'cancelled'
     WHERE unit_id = p_unit_id AND released_at IS NULL;
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

-- ── FIX 2: hold_unit — partners may hold only within agency-shared projects ─────────────────
CREATE OR REPLACE FUNCTION public.hold_unit(p_unit_id uuid, p_lead_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_tier      public.role_tier;
  v_uid       uuid := auth.uid();
  v_lead_owner uuid;
  v_visit     int;
  v_require   boolean;
  v_agency_id uuid;
  v_project   uuid;
  v_timer     int;
  v_carpet    numeric;
  v_version   int;
  v_hold_id   uuid;
  v_expires   timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();
  v_tier      := public.auth_role_tier();

  IF v_tier = 'receptionist' THEN
    RAISE EXCEPTION 'permission_denied: receptionist cannot hold units' USING ERRCODE = '42501';
  END IF;

  SELECT assigned_to_user_id, visit_count INTO v_lead_owner, v_visit
  FROM public.leads WHERE id = p_lead_id AND tenant_id = v_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'lead_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_tier IN ('front_line_rep', 'partner_agency') THEN
    IF v_lead_owner IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'not_your_lead' USING ERRCODE = '42501';
    END IF;
  ELSIF v_tier = 'team_leader' THEN
    IF NOT EXISTS (SELECT 1 FROM public.visible_user_ids() v WHERE v.user_id = v_lead_owner) THEN
      RAISE EXCEPTION 'not_your_lead' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT require_verified_before_hold INTO v_require FROM public.tenants WHERE id = v_tenant_id;
  IF COALESCE(v_require, false) AND COALESCE(v_visit, 0) < 1 THEN
    RAISE EXCEPTION 'hold_requires_verified_visit' USING ERRCODE = 'P0001';
  END IF;

  SELECT u.project_id, p.hold_timer_hours INTO v_project, v_timer
  FROM public.units u JOIN public.projects p ON p.id = u.project_id
  WHERE u.id = p_unit_id AND u.tenant_id = v_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unit_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_timer IS NULL THEN
    RAISE EXCEPTION 'hold_timer_not_configured' USING ERRCODE = 'P0001';
  END IF;

  -- FIX 2: a partner may only hold within a project shared to their agency (sandbox parity with 14.3)
  IF v_tier = 'partner_agency' THEN
    SELECT agency_id INTO v_agency_id FROM public.users WHERE id = v_uid;
    IF v_agency_id IS NULL OR NOT EXISTS (
         SELECT 1 FROM public.agency_projects ap
         WHERE ap.tenant_id = v_tenant_id AND ap.agency_id = v_agency_id AND ap.project_id = v_project
       ) THEN
      RAISE EXCEPTION 'project_not_shared' USING ERRCODE = '42501';
    END IF;
  END IF;

  UPDATE public.units
     SET status = 'hold', status_version = status_version + 1
   WHERE id = p_unit_id AND tenant_id = v_tenant_id AND status = 'available'
   RETURNING status_version, carpet_area_sqft INTO v_version, v_carpet;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unit_unavailable' USING ERRCODE = '42501';
  END IF;

  v_expires := now() + make_interval(hours => v_timer);

  BEGIN
    INSERT INTO public.unit_holds (tenant_id, unit_id, lead_id, holding_agent_id, carpet_area_sqft, held_at, expires_at)
    VALUES (v_tenant_id, p_unit_id, p_lead_id, v_uid, v_carpet, now(), v_expires)
    RETURNING id INTO v_hold_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'unit_unavailable' USING ERRCODE = '42501';
  END;

  PERFORM public.log_timeline_event(
    p_lead_id, 'unit_held'::public.timeline_event_type,
    jsonb_build_object('unit_id', p_unit_id, 'hold_id', v_hold_id, 'expires_at', v_expires)
  );

  RETURN jsonb_build_object('hold_id', v_hold_id, 'unit_id', p_unit_id, 'status_version', v_version, 'expires_at', v_expires);
END;
$$;

-- ── FIX 3: log_amendment — the lead must actually hold/own the unit ─────────────────────────
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

  SELECT status INTO v_status FROM public.units WHERE id = p_unit_id AND tenant_id = v_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unit_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_status NOT IN ('hold', 'sold') THEN
    RAISE EXCEPTION 'unit_not_amendable: amendments allowed only on hold/sold units (is %)', v_status USING ERRCODE = 'P0001';
  END IF;

  SELECT assigned_to_user_id INTO v_owner FROM public.leads WHERE id = p_lead_id AND tenant_id = v_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'lead_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.visible_user_ids() v WHERE v.user_id = v_owner) THEN
    RAISE EXCEPTION 'lead_not_visible' USING ERRCODE = '42501';
  END IF;

  -- FIX 3: the amendment's lead must actually hold (active) or have booked (converted) this unit
  IF NOT EXISTS (
    SELECT 1 FROM public.unit_holds h
    WHERE h.unit_id = p_unit_id AND h.lead_id = p_lead_id
      AND (h.released_at IS NULL OR h.outcome = 'converted')
  ) THEN
    RAISE EXCEPTION 'lead_not_linked_to_unit: this lead does not hold or own that unit' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.amendments (tenant_id, unit_id, lead_id, description, status, logged_by)
  VALUES (v_tenant_id, p_unit_id, p_lead_id, p_description, 'requested', auth.uid())
  RETURNING id INTO v_amd_id;

  PERFORM public.log_amendment_event(v_amd_id, 'logged', NULL, 'requested'::public.amendment_status, p_description);
  PERFORM public.log_timeline_event(
    p_lead_id, 'amendment_logged'::public.timeline_event_type,
    jsonb_build_object('amendment_id', v_amd_id, 'unit_id', p_unit_id, 'description', p_description)
  );

  RETURN v_amd_id;
END;
$$;

COMMIT;
