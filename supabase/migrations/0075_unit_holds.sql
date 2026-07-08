-- 0075_unit_holds.sql
-- Story 15.1 (Epic 15) — FR-52. unit_holds with a DB-level single-active-hold guarantee.
--
-- ── THE ACTIVE-HOLD INVARIANT (single source — 15.2 CAS + 15.3 cron both key off THIS exact predicate) ──
--     A hold is ACTIVE  ⇔  released_at IS NULL.
--   The partial UNIQUE index below enforces "at most one active hold per unit" at the DB level, so two
--   agents can NEVER both hold the same unit regardless of app logic. The CAS (15.2) inserts an active
--   hold + flips units.status under the unit row lock; the cron (15.3) sets released_at + outcome='expired'
--   on expiry. Both use released_at IS NULL — do not introduce a second "active" definition.
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

-- hold outcome (terminal reason; NULL while active) --------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'hold_outcome') THEN
    CREATE TYPE public.hold_outcome AS ENUM ('converted', 'released', 'expired', 'cancelled');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.unit_holds (
  id               uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id        uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  unit_id          uuid NOT NULL REFERENCES public.units(id)   ON DELETE CASCADE,
  lead_id          uuid NOT NULL REFERENCES public.leads(id)   ON DELETE RESTRICT,
  holding_agent_id uuid NOT NULL REFERENCES public.users(id)   ON DELETE RESTRICT,
  carpet_area_sqft numeric(10,2),                 -- snapshot at hold time
  held_at          timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz NOT NULL,
  released_at      timestamptz,                   -- NULL = ACTIVE (the invariant)
  outcome          public.hold_outcome,           -- NULL while active; set on release/convert/expire
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- at most ONE active hold per unit (the single-active guarantee)
CREATE UNIQUE INDEX IF NOT EXISTS unit_holds_one_active_idx
  ON public.unit_holds (unit_id) WHERE released_at IS NULL;

-- release sweep support (15.3): find active holds past expiry
CREATE INDEX IF NOT EXISTS unit_holds_active_expiry_idx
  ON public.unit_holds (expires_at) WHERE released_at IS NULL;

-- FK / scope indexes
CREATE INDEX IF NOT EXISTS unit_holds_tenant_idx ON public.unit_holds (tenant_id);
CREATE INDEX IF NOT EXISTS unit_holds_lead_idx   ON public.unit_holds (lead_id);
CREATE INDEX IF NOT EXISTS unit_holds_agent_idx  ON public.unit_holds (holding_agent_id);

ALTER TABLE public.unit_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unit_holds FORCE  ROW LEVEL SECURITY;

DROP POLICY IF EXISTS unit_holds_tenant_isolation ON public.unit_holds;
CREATE POLICY unit_holds_tenant_isolation ON public.unit_holds
  FOR ALL
  TO authenticated
  USING      (tenant_id = public.auth_tenant_id())
  WITH CHECK (tenant_id = public.auth_tenant_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.unit_holds TO authenticated;

COMMENT ON TABLE public.unit_holds IS
  'Story 15.1 — unit holds. ACTIVE ⇔ released_at IS NULL (single source for 15.2 CAS + 15.3 cron). Partial-unique (unit_id) WHERE released_at IS NULL = at most one active hold per unit.';

COMMIT;
