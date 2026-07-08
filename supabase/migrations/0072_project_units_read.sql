-- 0072_project_units_read.sql
-- Story 14.3 (Epic 14) — FR-49. Live availability grid read path (anti double-book).
--
-- Introduces agency_projects: the explicit project→agency share the §13.2 capability matrix
-- requires ("partners see only projects explicitly shared to the agency"). Arch §3.1 specced the
-- inventory tables but not this link table; added here as the home for partner project visibility.
--
-- get_project_units(project) is the authoritative, properly-scoped read:
--   • internal tiers → all tenant units for the project;
--   • partner_agency → ONLY if the project is shared to the caller's agency (else project_not_shared);
--   • cost_paise (margin) is returned ONLY to builder_head — NULL for everyone else (FR margin privacy).
-- The read never mutates (booking is Epic 15).
--
-- units is added to the supabase_realtime publication so clients get ≤5s status propagation.
-- NOTE: Realtime authorization uses RLS, which is tenant-scoped (not agency/project-scoped); a partner
-- subscribing directly would be tenant-bounded but not project-bounded. Authoritative scoping lives in
-- this RPC; tightening partner Realtime to shared-projects-only is a follow-on (clients only subscribe
-- to projects they opened via this RPC). Acceptable for V2 demo (internal sales floor).
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

-- 1. agency_projects — explicit project share to an external agency --------------------------
CREATE TABLE IF NOT EXISTS public.agency_projects (
  id          uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES public.tenants(id)  ON DELETE CASCADE,
  agency_id   uuid NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
  project_id  uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT agency_projects_unique UNIQUE (tenant_id, agency_id, project_id)
);

CREATE INDEX IF NOT EXISTS agency_projects_agency_idx  ON public.agency_projects (tenant_id, agency_id);
CREATE INDEX IF NOT EXISTS agency_projects_project_idx ON public.agency_projects (project_id);

ALTER TABLE public.agency_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agency_projects FORCE  ROW LEVEL SECURITY;

-- SELECT: any tenant member; DML: admin (builder_head) only — mirrors agencies (0057).
DROP POLICY IF EXISTS agency_projects_select       ON public.agency_projects;
DROP POLICY IF EXISTS agency_projects_admin_insert ON public.agency_projects;
DROP POLICY IF EXISTS agency_projects_admin_update ON public.agency_projects;
DROP POLICY IF EXISTS agency_projects_admin_delete ON public.agency_projects;

CREATE POLICY agency_projects_select ON public.agency_projects
  FOR SELECT TO authenticated
  USING (tenant_id = public.auth_tenant_id());

CREATE POLICY agency_projects_admin_insert ON public.agency_projects
  FOR INSERT TO authenticated
  WITH CHECK (tenant_id = public.auth_tenant_id() AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin');

CREATE POLICY agency_projects_admin_update ON public.agency_projects
  FOR UPDATE TO authenticated
  USING      (tenant_id = public.auth_tenant_id() AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin')
  WITH CHECK (tenant_id = public.auth_tenant_id() AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin');

CREATE POLICY agency_projects_admin_delete ON public.agency_projects
  FOR DELETE TO authenticated
  USING (tenant_id = public.auth_tenant_id() AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin');

GRANT SELECT, INSERT, UPDATE, DELETE ON public.agency_projects TO authenticated;

COMMENT ON TABLE public.agency_projects IS
  'Story 14.3 — explicit project→agency share. A partner_agency user sees a project''s inventory only if a row here links their agency to it. Admin-only DML.';

-- 2. Realtime: publish units status changes -------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'units'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.units;
  END IF;
END $$;

-- 3. get_project_units — scoped read, margin-aware -----------------------------------------
CREATE OR REPLACE FUNCTION public.get_project_units(p_project_id uuid)
RETURNS TABLE (
  unit_id          uuid,
  tower_id         uuid,
  tower_name       text,
  unit_no          text,
  floor            int,
  configuration    text,
  carpet_area_sqft numeric,
  status           public.unit_status,
  list_price_paise bigint,
  cost_paise       bigint,
  status_version   int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_tier      public.role_tier;
  v_agency_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();
  v_tier      := public.auth_role_tier();

  IF NOT EXISTS (SELECT 1 FROM public.projects WHERE id = p_project_id AND tenant_id = v_tenant_id) THEN
    RAISE EXCEPTION 'project_not_found' USING ERRCODE = 'P0001';
  END IF;

  -- partner sandbox: only agency-shared projects
  IF v_tier = 'partner_agency' THEN
    SELECT u.agency_id INTO v_agency_id FROM public.users u WHERE u.id = auth.uid();
    IF v_agency_id IS NULL OR NOT EXISTS (
         SELECT 1 FROM public.agency_projects ap
         WHERE ap.tenant_id = v_tenant_id AND ap.agency_id = v_agency_id AND ap.project_id = p_project_id
       ) THEN
      RAISE EXCEPTION 'project_not_shared' USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u.tower_id,
    t.name,
    u.unit_no,
    u.floor,
    u.configuration,
    u.carpet_area_sqft,
    u.status,
    u.list_price_paise,
    CASE WHEN v_tier = 'builder_head' THEN u.cost_paise ELSE NULL END,   -- margin: head only
    u.status_version
  FROM public.units u
  LEFT JOIN public.towers t ON t.id = u.tower_id
  WHERE u.tenant_id = v_tenant_id
    AND u.project_id = p_project_id
  ORDER BY u.floor NULLS LAST, u.unit_no;
END;
$$;

REVOKE ALL ON FUNCTION public.get_project_units(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_project_units(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_project_units(uuid) IS
  'Story 14.3 — availability grid read. Internal: all tenant units; partner_agency: only agency-shared projects (else project_not_shared). cost_paise returned only to builder_head. Read-only.';

COMMIT;
