-- 0076_hold_unit.sql
-- Story 15.2 (Epic 15) — FR-52. Place a hold on an available unit via compare-and-swap.
--
-- Two stacked guards make a double-book impossible:
--   1. CAS: UPDATE units SET status='hold', status_version+1 WHERE id=? AND status='available'.
--      The UPDATE takes the unit row lock, so concurrent attempts serialize; exactly one sees
--      status='available' and wins. The loser gets 0 rows → clean `unit_unavailable` (NOT a 500).
--   2. Backstop: unit_holds_one_active_idx partial unique (0075). If anything slipped past (1), the
--      hold INSERT raises unique_violation → mapped to `unit_unavailable` (never bubbles as 23505/500).
-- No lock is held across customer think-time — the hold is a committed row with expires_at.
--
-- require_verified_before_hold: tenant flag (default OFF, keeps Epic 15 independent of Epic 13). When
-- ON, the lead must have visit_count > 0. Ownership: front_line_rep/partner hold OWN leads only;
-- team_leader within their visible subtree; builder_head any tenant lead; receptionist never.
--
-- 'unit_held' added to timeline_event_type (bare ADD VALUE before BEGIN; used only at call time).
-- File-based migration; never MCP apply.

ALTER TYPE public.timeline_event_type ADD VALUE IF NOT EXISTS 'unit_held';

BEGIN;

ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS require_verified_before_hold boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.tenants.require_verified_before_hold IS
  'Story 15.2 — when true, hold_unit requires the lead to have a verified visit (visit_count > 0). Default false.';

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

  -- lead must be in the tenant
  SELECT assigned_to_user_id, visit_count INTO v_lead_owner, v_visit
  FROM public.leads WHERE id = p_lead_id AND tenant_id = v_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'lead_not_found' USING ERRCODE = 'P0001';
  END IF;

  -- ownership scope
  IF v_tier IN ('front_line_rep', 'partner_agency') THEN
    IF v_lead_owner IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'not_your_lead' USING ERRCODE = '42501';
    END IF;
  ELSIF v_tier = 'team_leader' THEN
    IF NOT EXISTS (SELECT 1 FROM public.visible_user_ids() v WHERE v.user_id = v_lead_owner) THEN
      RAISE EXCEPTION 'not_your_lead' USING ERRCODE = '42501';
    END IF;
  END IF;  -- builder_head: any lead in tenant

  -- verified-visit gate (flag default OFF)
  SELECT require_verified_before_hold INTO v_require FROM public.tenants WHERE id = v_tenant_id;
  IF COALESCE(v_require, false) AND COALESCE(v_visit, 0) < 1 THEN
    RAISE EXCEPTION 'hold_requires_verified_visit' USING ERRCODE = 'P0001';
  END IF;

  -- unit must exist in tenant; project hold timer must be configured
  SELECT u.project_id, p.hold_timer_hours INTO v_project, v_timer
  FROM public.units u JOIN public.projects p ON p.id = u.project_id
  WHERE u.id = p_unit_id AND u.tenant_id = v_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unit_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_timer IS NULL THEN
    RAISE EXCEPTION 'hold_timer_not_configured' USING ERRCODE = 'P0001';
  END IF;

  -- GUARD 1 — CAS available -> hold
  UPDATE public.units
     SET status = 'hold', status_version = status_version + 1
   WHERE id = p_unit_id AND tenant_id = v_tenant_id AND status = 'available'
   RETURNING status_version, carpet_area_sqft INTO v_version, v_carpet;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unit_unavailable' USING ERRCODE = '42501';
  END IF;

  v_expires := now() + make_interval(hours => v_timer);

  -- GUARD 2 — single-active-hold partial unique (0075) as a backstop
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

  RETURN jsonb_build_object(
    'hold_id',        v_hold_id,
    'unit_id',        p_unit_id,
    'status_version', v_version,
    'expires_at',     v_expires
  );
END;
$$;

REVOKE ALL ON FUNCTION public.hold_unit(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.hold_unit(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.hold_unit(uuid, uuid) IS
  'Story 15.2 — CAS hold (available->hold) + unit_holds insert + unit_held timeline. Loser of a race gets clean unit_unavailable. Ownership-scoped; receptionist denied; honours require_verified_before_hold.';

COMMIT;
