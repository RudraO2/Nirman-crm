-- 0086_unit_crud.sql
-- Per-unit add / rename / delete so builder_head can fix the exceptions the bulk
-- grid can't express (a merged flat, an extra shop, a one-off number). Mirrors the
-- 0074 guard idiom: builder_head only, tenant-scoped, and hold|sold units are
-- locked (must be released first) so we never invalidate a live hold or a sale.
--
--   add_unit    -> uuid  : insert one unit (duplicate_unit on unique clash); emits new_stock.
--   rename_unit -> void  : change unit_no; blocked on hold|sold; duplicate_unit on clash.
--   delete_unit -> void  : hard-delete; blocked on hold|sold; unit_has_history if referenced.
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

-- 1. add_unit ---------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.add_unit(
  p_project_id        uuid,
  p_tower_id          uuid,
  p_unit_no           text,
  p_floor             int     DEFAULT NULL,
  p_configuration     text    DEFAULT NULL,
  p_carpet_area_sqft  numeric DEFAULT NULL,
  p_list_price_paise  bigint  DEFAULT NULL,
  p_cost_paise        bigint  DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_unit_id   uuid;
  v_unit_no   text := btrim(COALESCE(p_unit_no, ''));
BEGIN
  IF public.auth_role_tier() IS DISTINCT FROM 'builder_head' THEN
    RAISE EXCEPTION 'permission_denied: builder_head only' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  IF v_unit_no = '' THEN
    RAISE EXCEPTION 'invalid_unit_no: unit_no is required' USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.projects WHERE id = p_project_id AND tenant_id = v_tenant_id) THEN
    RAISE EXCEPTION 'project_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF p_tower_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.towers WHERE id = p_tower_id AND project_id = p_project_id AND tenant_id = v_tenant_id) THEN
    RAISE EXCEPTION 'tower_not_found' USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    INSERT INTO public.units (
      tenant_id, project_id, tower_id, unit_no, floor, configuration,
      carpet_area_sqft, list_price_paise, cost_paise
    )
    VALUES (
      v_tenant_id, p_project_id, p_tower_id, v_unit_no, p_floor, p_configuration,
      p_carpet_area_sqft, p_list_price_paise, p_cost_paise
    )
    RETURNING id INTO v_unit_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_unit: unit % already exists in this project/tower', v_unit_no
      USING ERRCODE = 'P0001';
  END;

  PERFORM public.emit_inventory_changed(v_unit_id, 'new_stock');
  RETURN v_unit_id;
END;
$$;

REVOKE ALL ON FUNCTION public.add_unit(uuid, uuid, text, int, text, numeric, bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_unit(uuid, uuid, text, int, text, numeric, bigint, bigint) TO authenticated;

COMMENT ON FUNCTION public.add_unit(uuid, uuid, text, int, text, numeric, bigint, bigint) IS
  '0086 — builder_head adds one unit. duplicate_unit on unique clash; emits inventory_changed new_stock.';

-- 2. rename_unit ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rename_unit(
  p_unit_id   uuid,
  p_new_unit_no text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_status    public.unit_status;
  v_new       text := btrim(COALESCE(p_new_unit_no, ''));
BEGIN
  IF public.auth_role_tier() IS DISTINCT FROM 'builder_head' THEN
    RAISE EXCEPTION 'permission_denied: builder_head only' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  IF v_new = '' THEN
    RAISE EXCEPTION 'invalid_unit_no: unit_no is required' USING ERRCODE = 'P0001';
  END IF;

  SELECT status INTO v_status
  FROM public.units
  WHERE id = p_unit_id AND tenant_id = v_tenant_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unit_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_status IN ('hold', 'sold') THEN
    RAISE EXCEPTION 'unit_locked_release_first: unit is % — a builder_head must release it before renaming', v_status
      USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    UPDATE public.units SET unit_no = v_new
     WHERE id = p_unit_id AND tenant_id = v_tenant_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_unit: unit % already exists in this project/tower', v_new
      USING ERRCODE = 'P0001';
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.rename_unit(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rename_unit(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.rename_unit(uuid, text) IS
  '0086 — builder_head renames a unit. Blocked on hold|sold (unit_locked_release_first); duplicate_unit on clash.';

-- 3. delete_unit ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_unit(p_unit_id uuid)
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
  IF v_status IN ('hold', 'sold') THEN
    RAISE EXCEPTION 'unit_locked_release_first: unit is % — release it before deleting', v_status
      USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    DELETE FROM public.units WHERE id = p_unit_id AND tenant_id = v_tenant_id;
  EXCEPTION WHEN foreign_key_violation THEN
    -- a hold/booking/amendment still references this unit — keep history intact.
    RAISE EXCEPTION 'unit_has_history: unit has holds/bookings/amendments and cannot be deleted — withdraw it instead'
      USING ERRCODE = 'P0001';
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_unit(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_unit(uuid) TO authenticated;

COMMENT ON FUNCTION public.delete_unit(uuid) IS
  '0086 — builder_head hard-deletes a unit. Blocked on hold|sold; unit_has_history if referenced by holds/bookings/amendments.';

COMMIT;
