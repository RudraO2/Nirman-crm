-- 0074_inventory_change_guard.sql
-- Story 14.5 (Epic 14) — FR-51. Inventory-change notify producer + held/sold withdraw protection.
--
-- Owns the notify-RULE + the withdraw/reprice GUARD (the hold/release transitions themselves are
-- Epic 15). Resolves the 14↔15 race: a developer/inventory edit cannot silently invalidate a live
-- hold or a sold unit — those must be released by a builder_head first.
--
-- 1. update_unit_listing  — reprice / edit a unit; REJECTS if status is hold|sold
--    (unit_locked_release_first). builder_head only.
-- 2. change_unit_inventory_state — builder_head state transitions that 14 owns:
--      withdraw      available → blocked          (held/sold → unit_locked_release_first)
--      restock       blocked   → available        (emits inventory_changed kind=new_stock)
--      force_release hold|sold → available        (head override; emits kind=release)
--    Optimistic CAS on status_version (unit_version_conflict); bumps status_version.
-- 3. emit_inventory_changed(unit, kind) — domain_events producer (NO margin in payload). Reused by
--    Epic 15 release/expire so hold→available naturally notifies. The send-* edge fn (deferred) fans
--    out FCM honouring partner visibility (no cost_paise ever travels in the event).
--
-- State machine source: 0070 header. File-based migration; never MCP apply.

BEGIN;

-- domain_events event_type is TEXT (not an enum) — no ALTER TYPE needed (checked 0026/0052 usage).

-- 1. emit_inventory_changed -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.emit_inventory_changed(p_unit_id uuid, p_kind text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id  uuid;
  v_project_id uuid;
BEGIN
  SELECT tenant_id, project_id INTO v_tenant_id, v_project_id
  FROM public.units WHERE id = p_unit_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- payload deliberately carries NO cost_paise/margin (partner-safe; consumers scope per-tier).
  INSERT INTO public.domain_events (tenant_id, event_type, payload, occurred_at)
  VALUES (
    v_tenant_id, 'inventory_changed',
    jsonb_build_object('unit_id', p_unit_id, 'project_id', v_project_id, 'kind', p_kind),
    now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.emit_inventory_changed(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.emit_inventory_changed(uuid, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.emit_inventory_changed(uuid, text) IS
  'Story 14.5 — emits inventory_changed domain_event (margin-free) for the FCM fan-out. Reused by Epic 15 release/expire so hold->available notifies the sales team.';

-- 2. update_unit_listing — reprice/edit; held/sold protected ---------------------------------
CREATE OR REPLACE FUNCTION public.update_unit_listing(
  p_unit_id          uuid,
  p_list_price_paise bigint  DEFAULT NULL,
  p_cost_paise       bigint  DEFAULT NULL,
  p_configuration    text    DEFAULT NULL,
  p_carpet_area_sqft numeric DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_status    public.unit_status;
BEGIN
  IF public.auth_role_tier() IS DISTINCT FROM 'builder_head' THEN
    RAISE EXCEPTION 'permission_denied: builder_head only' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  SELECT status INTO v_status
  FROM public.units
  WHERE id = p_unit_id AND tenant_id = v_tenant_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unit_not_found' USING ERRCODE = 'P0001';
  END IF;

  -- cannot reprice/edit a unit under a live hold or already sold — release it first.
  IF v_status IN ('hold', 'sold') THEN
    RAISE EXCEPTION 'unit_locked_release_first: unit is % — a builder_head must release it before editing', v_status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.units
     SET list_price_paise = COALESCE(p_list_price_paise, list_price_paise),
         cost_paise       = COALESCE(p_cost_paise,       cost_paise),
         configuration    = COALESCE(p_configuration,    configuration),
         carpet_area_sqft = COALESCE(p_carpet_area_sqft, carpet_area_sqft)
   WHERE id = p_unit_id AND tenant_id = v_tenant_id;
END;
$$;

REVOKE ALL ON FUNCTION public.update_unit_listing(uuid, bigint, bigint, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_unit_listing(uuid, bigint, bigint, text, numeric) TO authenticated;

COMMENT ON FUNCTION public.update_unit_listing(uuid, bigint, bigint, text, numeric) IS
  'Story 14.5 — builder_head reprice/edit a unit. Rejects hold|sold units (unit_locked_release_first) — resolves the 14<->15 race.';

-- 3. change_unit_inventory_state — head transitions (14 owns) + CAS + notify -----------------
CREATE OR REPLACE FUNCTION public.change_unit_inventory_state(
  p_unit_id          uuid,
  p_action           text,             -- 'withdraw' | 'restock' | 'force_release'
  p_expected_version int DEFAULT NULL  -- optimistic CAS token (units.status_version)
)
RETURNS int                            -- new status_version
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
  FROM public.units
  WHERE id = p_unit_id AND tenant_id = v_tenant_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unit_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF p_expected_version IS NOT NULL AND p_expected_version <> v_version THEN
    RAISE EXCEPTION 'unit_version_conflict: expected % but is %', p_expected_version, v_version
      USING ERRCODE = 'P0001';
  END IF;

  IF p_action = 'withdraw' THEN
    IF v_status IN ('hold', 'sold') THEN
      RAISE EXCEPTION 'unit_locked_release_first: cannot withdraw a % unit — release it first', v_status
        USING ERRCODE = 'P0001';
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

  -- notify on stock becoming available again
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
  'Story 14.5 — builder_head inventory transitions: withdraw (available->blocked), restock (blocked->available), force_release (hold|sold->available override). CAS on status_version; emits inventory_changed on ->available.';

COMMIT;
