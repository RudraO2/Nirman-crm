-- 0070_inventory.sql
-- Story 14.1 (Epic 14) — FR-48. Inventory schema: towers, units, unit status lifecycle.
-- (Planned as "0058" in epics.md before Epic 12-13 consumed 0057-0069; real next number is 0070.)
--
-- ── UNIT STATUS — canonical state machine (single source for Epic 15 holds + Epic 16 amendments) ──
--   available → hold      : front-line/leader places a temporary hold (Story 15.2, CAS on status_version)
--   hold      → sold      : confirm booking on reception verification (Story 15.4)
--   hold      → available : hold auto-released by timer or manual release (Story 15.3)
--   available → blocked   : builder_head withdraws stock from sale (Story 14.5)
--   blocked   → available : builder_head returns stock to sale (Story 14.5)
--   sold      → available : builder_head OVERRIDE ONLY (cancellation/correction) (Story 14.5/16)
-- No other transitions are legal. hold/sold units cannot be withdrawn (→blocked) without builder_head (14.5).
-- status_version is the optimistic-concurrency token: every status change bumps it (CAS in 15.2 guards
-- against two reps grabbing the same unit). cost_paise is margin — NEVER selected by non-builder_head
-- read paths (14.3 / 12.6 partner sandbox).
--
-- Mirrors RLS+FORCE+tenant-policy shape from 0009. Prices in paise (consistent with leads.budget_*).
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

-- 1. Per-project hold timer (hours). NULL until a grid is created (14.2 requires it). ----------
ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS hold_timer_hours int;

COMMENT ON COLUMN public.projects.hold_timer_hours IS
  'Story 14.1 — per-project auto-release window (hours) for unit holds. Set at grid creation (14.2). No global default.';

-- 2. unit_status enum ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'unit_status') THEN
    CREATE TYPE public.unit_status AS ENUM ('available', 'hold', 'sold', 'blocked');
  END IF;
END $$;

-- 3. towers -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.towers (
  id          uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  project_id  uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  name        text NOT NULL,
  sort_order  int  NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT towers_tenant_project_name_unique UNIQUE (tenant_id, project_id, name)
);

CREATE INDEX IF NOT EXISTS towers_tenant_project_idx ON public.towers (tenant_id, project_id);

ALTER TABLE public.towers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.towers FORCE  ROW LEVEL SECURITY;

DROP POLICY IF EXISTS towers_tenant_isolation ON public.towers;
CREATE POLICY towers_tenant_isolation ON public.towers
  FOR ALL
  TO authenticated
  USING      (tenant_id = public.auth_tenant_id())
  WITH CHECK (tenant_id = public.auth_tenant_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.towers TO authenticated;

CREATE TRIGGER towers_set_updated_at
  BEFORE UPDATE ON public.towers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 4. units --------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.units (
  id                uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id         uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  project_id        uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  tower_id          uuid REFERENCES public.towers(id) ON DELETE SET NULL,
  unit_no           text NOT NULL,
  floor             int,
  configuration     text,                                         -- e.g. '2BHK', '3BHK'
  carpet_area_sqft  numeric(10,2),
  status            public.unit_status NOT NULL DEFAULT 'available',
  list_price_paise  bigint,
  cost_paise        bigint,                                       -- MARGIN: builder_head-only read paths
  status_version    int  NOT NULL DEFAULT 0,                      -- optimistic-concurrency token (CAS, 15.2)
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

-- unique unit_no within a project, treating tower-less units as one bucket (COALESCE → nil uuid)
CREATE UNIQUE INDEX IF NOT EXISTS units_project_tower_unit_no_unique
  ON public.units (tenant_id, project_id, COALESCE(tower_id, '00000000-0000-0000-0000-000000000000'::uuid), unit_no);

CREATE INDEX IF NOT EXISTS units_tenant_project_status_idx ON public.units (tenant_id, project_id, status);
CREATE INDEX IF NOT EXISTS units_tower_idx ON public.units (tower_id);

ALTER TABLE public.units ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.units FORCE  ROW LEVEL SECURITY;

DROP POLICY IF EXISTS units_tenant_isolation ON public.units;
CREATE POLICY units_tenant_isolation ON public.units
  FOR ALL
  TO authenticated
  USING      (tenant_id = public.auth_tenant_id())
  WITH CHECK (tenant_id = public.auth_tenant_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.units TO authenticated;

CREATE TRIGGER units_set_updated_at
  BEFORE UPDATE ON public.units
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE  public.units IS
  'Story 14.1 — sellable units. status lifecycle documented in 0070 header. cost_paise is margin (builder_head-only). status_version = CAS token for holds (15.2).';

COMMIT;
