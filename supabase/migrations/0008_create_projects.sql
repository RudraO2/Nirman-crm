-- Story 2.1 — Projects reference table
-- FRs: FR-1 (Project multi-select on Lead form), FR-21 (Future Pool project-match trigger)
-- NFRs: NFR-11 (tenant_id on every table), NFR-12 (query-layer tenant scoping)
-- Architecture decisions: 1 (Postgres), 2 (RLS), 5 (declarative migrations)
--
-- Roll-forward only. Never edit after apply.

-- ────────────────────────────────────────────────────────────────────────────
-- projects
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.projects (
  id         uuid        PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id  uuid        NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  name       text        NOT NULL,
  is_active  boolean     NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.projects IS
  'Story 2.1 — Real-estate project catalogue. Leads reference projects via lead_projects junction.';

-- FK index (every FK indexed per arch §Database Patterns)
CREATE INDEX IF NOT EXISTS projects_tenant_id_idx
  ON public.projects (tenant_id);

-- ────────────────────────────────────────────────────────────────────────────
-- RLS
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects FORCE  ROW LEVEL SECURITY;

DROP POLICY IF EXISTS projects_tenant_isolation ON public.projects;
CREATE POLICY projects_tenant_isolation ON public.projects
  FOR ALL
  TO authenticated
  USING      (tenant_id = public.auth_tenant_id())
  WITH CHECK (tenant_id = public.auth_tenant_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.projects TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- Seed — V1 default project
-- ────────────────────────────────────────────────────────────────────────────
INSERT INTO public.projects (tenant_id, name)
VALUES ('00000000-0000-0000-0000-000000000001', 'The Velocity')
ON CONFLICT DO NOTHING;
