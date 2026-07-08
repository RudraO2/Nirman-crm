-- 0085_flexible_unit_grid.sql
-- Flexible numbering for generate_unit_grid. Adds optional params so real-world
-- towers (ground floor, skipped 13th, letter prefixes, zero-padded numbers,
-- non-1 starts) can be generated without hand-editing every unit.
--
-- New optional params (all defaulted so the previous behaviour is unchanged):
--   p_start_floor  int      DEFAULT 1     -- first floor number (e.g. 0 for ground)
--   p_unit_start   int      DEFAULT 1     -- first position on each floor
--   p_prefix       text     DEFAULT ''    -- prepended to every unit_no (e.g. 'A-')
--   p_pad_width    int      DEFAULT 0     -- zero-pad the numeric part to N digits (0 = off)
--   p_skip_floors  int[]    DEFAULT '{}'  -- floor numbers to omit entirely (e.g. '{13}')
--
-- Base number stays floor*100 + position; prefix/pad wrap it. config_map is still
-- keyed by position. Idempotent via the 0070 unique index. builder_head only.
--
-- Replaces the 0071 function — must DROP the old signature first (adding defaulted
-- params creates a second overload → ambiguous-call errors otherwise).
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

DROP FUNCTION IF EXISTS public.generate_unit_grid(uuid, uuid, int, int, jsonb, int, numeric, bigint, bigint);

CREATE OR REPLACE FUNCTION public.generate_unit_grid(
  p_project_id        uuid,
  p_tower_id          uuid,
  p_floors            int,
  p_units_per_floor   int,
  p_config_map        jsonb,
  p_hold_timer_hours  int,
  p_carpet_area_sqft  numeric DEFAULT NULL,
  p_list_price_paise  bigint  DEFAULT NULL,
  p_cost_paise        bigint  DEFAULT NULL,
  p_start_floor       int     DEFAULT 1,
  p_unit_start        int     DEFAULT 1,
  p_prefix            text    DEFAULT '',
  p_pad_width         int     DEFAULT 0,
  p_skip_floors       int[]   DEFAULT '{}'
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
  v_prefix    text := COALESCE(p_prefix, '');
  v_pad       int  := COALESCE(p_pad_width, 0);
  v_skip      int[] := COALESCE(p_skip_floors, '{}');
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
  IF p_start_floor IS NULL OR p_unit_start IS NULL OR p_unit_start < 0 THEN
    RAISE EXCEPTION 'invalid_grid: start_floor and unit_start must be set (unit_start >= 0)' USING ERRCODE = 'P0001';
  END IF;
  IF v_pad < 0 OR v_pad > 12 THEN
    RAISE EXCEPTION 'invalid_grid: pad_width must be between 0 and 12' USING ERRCODE = 'P0001';
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

  INSERT INTO public.units (
    tenant_id, project_id, tower_id, unit_no, floor, configuration,
    carpet_area_sqft, list_price_paise, cost_paise
  )
  SELECT
    v_tenant_id, p_project_id, p_tower_id,
    v_prefix || CASE
                  WHEN v_pad > 0 THEN lpad((f.floor * 100 + u.pos)::text, v_pad, '0')
                  ELSE (f.floor * 100 + u.pos)::text
                END,
    f.floor,
    p_config_map ->> u.pos::text,
    p_carpet_area_sqft, p_list_price_paise, p_cost_paise
  FROM generate_series(p_start_floor, p_start_floor + p_floors - 1)        AS f(floor)
  CROSS JOIN generate_series(p_unit_start, p_unit_start + p_units_per_floor - 1) AS u(pos)
  WHERE f.floor <> ALL (v_skip)
  ON CONFLICT (tenant_id, project_id, COALESCE(tower_id, '00000000-0000-0000-0000-000000000000'::uuid), unit_no)
  DO NOTHING;

  GET DIAGNOSTICS v_created = ROW_COUNT;

  -- attempted = full grid minus the skipped floors
  v_attempted := (p_floors - (
                    SELECT count(*) FROM generate_series(p_start_floor, p_start_floor + p_floors - 1) AS g(floor)
                    WHERE g.floor = ANY (v_skip)
                  )) * p_units_per_floor;

  RETURN jsonb_build_object(
    'created',          v_created,
    'skipped_existing', v_attempted - v_created,
    'attempted',        v_attempted,
    'hold_timer_hours', p_hold_timer_hours
  );
END;
$$;

REVOKE ALL ON FUNCTION public.generate_unit_grid(uuid, uuid, int, int, jsonb, int, numeric, bigint, bigint, int, int, text, int, int[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_unit_grid(uuid, uuid, int, int, jsonb, int, numeric, bigint, bigint, int, int, text, int, int[]) TO authenticated;

COMMENT ON FUNCTION public.generate_unit_grid(uuid, uuid, int, int, jsonb, int, numeric, bigint, bigint, int, int, text, int, int[]) IS
  'Story 14.2 (+0085 flexible numbering) — builder_head only. Bulk-creates units floors x units_per_floor idempotently; unit_no = prefix || pad(floor*100+pos). Supports start_floor, unit_start, prefix, pad_width, skip_floors[]. Requires + persists project hold_timer_hours. Returns {created, skipped_existing, attempted, hold_timer_hours}.';

COMMIT;
