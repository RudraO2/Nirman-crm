-- 0071_generate_unit_grid.sql
-- Story 14.2 (Epic 14) — FR-48. Bulk-create a project's units in one transaction.
--
-- generate_unit_grid(project, tower, floors, units_per_floor, config_map, hold_timer_hours, ...)
--   • builder_head only (auth_role_tier guard).
--   • Set-based insert over generate_series(floors) × generate_series(units_per_floor):
--       unit_no = (floor*100 + position) as text; configuration = config_map ->> position.
--   • config_map is a jsonb {"<position>": "<configuration>"} applied identically on every floor
--       — e.g. {"1":"2BHK",..,"6":"2BHK","7":"3BHK",..,"12":"3BHK"} → a 2/3 BHK mix per floor.
--   • Idempotent: ON CONFLICT on the (tenant,project,COALESCE(tower,nil),unit_no) unique index (0070).
--   • hold_timer_hours is REQUIRED and persisted on the project at grid creation (no global default).
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

CREATE OR REPLACE FUNCTION public.generate_unit_grid(
  p_project_id        uuid,
  p_tower_id          uuid,
  p_floors            int,
  p_units_per_floor   int,
  p_config_map        jsonb,
  p_hold_timer_hours  int,
  p_carpet_area_sqft  numeric DEFAULT NULL,
  p_list_price_paise  bigint  DEFAULT NULL,
  p_cost_paise        bigint  DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_created   int;
  v_attempted int;
BEGIN
  IF public.auth_role_tier() IS DISTINCT FROM 'builder_head' THEN
    RAISE EXCEPTION 'permission_denied: builder_head only' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  IF p_floors IS NULL OR p_floors < 1 OR p_units_per_floor IS NULL OR p_units_per_floor < 1 THEN
    RAISE EXCEPTION 'invalid_grid: floors and units_per_floor must be >= 1' USING ERRCODE = 'P0001';
  END IF;
  IF p_hold_timer_hours IS NULL OR p_hold_timer_hours < 1 THEN
    RAISE EXCEPTION 'hold_timer_required: hold_timer_hours must be set (>=1) at grid creation' USING ERRCODE = 'P0001';
  END IF;

  -- project must belong to caller's tenant
  IF NOT EXISTS (SELECT 1 FROM public.projects WHERE id = p_project_id AND tenant_id = v_tenant_id) THEN
    RAISE EXCEPTION 'project_not_found' USING ERRCODE = 'P0001';
  END IF;
  -- tower (if given) must belong to the same project + tenant
  IF p_tower_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.towers WHERE id = p_tower_id AND project_id = p_project_id AND tenant_id = v_tenant_id) THEN
    RAISE EXCEPTION 'tower_not_found' USING ERRCODE = 'P0001';
  END IF;

  -- persist the per-project hold timer
  UPDATE public.projects SET hold_timer_hours = p_hold_timer_hours
   WHERE id = p_project_id AND tenant_id = v_tenant_id;

  v_attempted := p_floors * p_units_per_floor;

  INSERT INTO public.units (
    tenant_id, project_id, tower_id, unit_no, floor, configuration,
    carpet_area_sqft, list_price_paise, cost_paise
  )
  SELECT
    v_tenant_id, p_project_id, p_tower_id,
    (f.floor * 100 + u.pos)::text,
    f.floor,
    p_config_map ->> u.pos::text,
    p_carpet_area_sqft, p_list_price_paise, p_cost_paise
  FROM generate_series(1, p_floors)          AS f(floor)
  CROSS JOIN generate_series(1, p_units_per_floor) AS u(pos)
  ON CONFLICT (tenant_id, project_id, COALESCE(tower_id, '00000000-0000-0000-0000-000000000000'::uuid), unit_no)
  DO NOTHING;

  GET DIAGNOSTICS v_created = ROW_COUNT;

  RETURN jsonb_build_object(
    'created',          v_created,
    'skipped_existing', v_attempted - v_created,
    'attempted',        v_attempted,
    'hold_timer_hours', p_hold_timer_hours
  );
END;
$$;

REVOKE ALL ON FUNCTION public.generate_unit_grid(uuid, uuid, int, int, jsonb, int, numeric, bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_unit_grid(uuid, uuid, int, int, jsonb, int, numeric, bigint, bigint) TO authenticated;

COMMENT ON FUNCTION public.generate_unit_grid(uuid, uuid, int, int, jsonb, int, numeric, bigint, bigint) IS
  'Story 14.2 — builder_head only. Bulk-creates units (floors × units_per_floor) idempotently; unit_no=floor*100+pos, configuration=config_map->>pos. Requires + persists project hold_timer_hours. Returns {created, skipped_existing, attempted, hold_timer_hours}.';

COMMIT;
