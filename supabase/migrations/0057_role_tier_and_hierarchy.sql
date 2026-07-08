-- 0057_role_tier_and_hierarchy.sql
-- Story 12.1 (Epic 12 — Org Hierarchy & Role Tiers) — FR-39.
-- Source: architecture-builder-ops-v2.md §1.1, §2.1, §13.1.
--
-- ADDITIVE ONLY. Does NOT touch the user_role enum ('admin','employee') or the JWT
-- `role` claim — those remain the coarse security boundary the 17 hardened RPCs depend on
-- (arch §1.1). A new role_tier dimension carries the fine grain; auth_role_tier() falls back
-- to a tier derived from the role claim so existing JWTs keep working until 12.3 stamps them.
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.
--
-- Adds:
--   1. enum role_tier (6 values incl. receptionist — gate-not-own).
--   2. agencies table (external partner orgs; sibling branch) + tenant RLS.
--   3. users.role_tier / reports_to_user_id / is_external / agency_id (+ backfill + indexes).
--   4. auth_role_tier() helper (claim with role-derived fallback).

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. role_tier enum (mirrors codebase enum convention: user_role, lead_status)
-- ────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'role_tier') THEN
    CREATE TYPE public.role_tier AS ENUM (
      'super_admin', 'builder_head', 'team_leader', 'front_line_rep', 'partner_agency', 'receptionist'
    );
  END IF;
END
$$;

COMMENT ON TYPE public.role_tier IS
  'Story 12.1 — fine-grained org tier. Coarse role (admin/employee) is UNCHANGED. builder_head/super_admin map to role=admin; team_leader/front_line_rep/partner_agency/receptionist map to role=employee. receptionist gates visits, does not own leads.';

-- ────────────────────────────────────────────────────────────────────────────
-- 2. agencies — external partner organisations (tenant-scoped sibling branch)
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.agencies (
  id          uuid        PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  name        text        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.agencies IS
  'Story 12.1 — external partner/agency orgs. partner_agency users belong to one agency; leads they source carry leads.source_agency_id. Sandboxed from internal data (FR-40).';

CREATE INDEX IF NOT EXISTS agencies_tenant_id_idx ON public.agencies (tenant_id);

ALTER TABLE public.agencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agencies FORCE  ROW LEVEL SECURITY;

-- SELECT: any authenticated member of the tenant (so the team can see agency names).
-- DML: admin (builder_head) only — mirrors the users policy split in 0003.
DROP POLICY IF EXISTS agencies_tenant_isolation ON public.agencies;
DROP POLICY IF EXISTS agencies_select       ON public.agencies;
DROP POLICY IF EXISTS agencies_admin_insert ON public.agencies;
DROP POLICY IF EXISTS agencies_admin_update ON public.agencies;
DROP POLICY IF EXISTS agencies_admin_delete ON public.agencies;

CREATE POLICY agencies_select ON public.agencies
  FOR SELECT TO authenticated
  USING (tenant_id = public.auth_tenant_id());

CREATE POLICY agencies_admin_insert ON public.agencies
  FOR INSERT TO authenticated
  WITH CHECK (
    tenant_id = public.auth_tenant_id()
    AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin'
  );

CREATE POLICY agencies_admin_update ON public.agencies
  FOR UPDATE TO authenticated
  USING (
    tenant_id = public.auth_tenant_id()
    AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin'
  )
  WITH CHECK (
    tenant_id = public.auth_tenant_id()
    AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin'
  );

CREATE POLICY agencies_admin_delete ON public.agencies
  FOR DELETE TO authenticated
  USING (
    tenant_id = public.auth_tenant_id()
    AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin'
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.agencies TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. users hierarchy columns
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS role_tier           public.role_tier,
  ADD COLUMN IF NOT EXISTS reports_to_user_id  uuid REFERENCES public.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_external         boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS agency_id           uuid REFERENCES public.agencies(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.users.role_tier IS
  'Story 12.1 — fine-grained tier. NULL allowed until backfilled; auth_role_tier() derives a tier from role when the JWT claim is absent.';
COMMENT ON COLUMN public.users.reports_to_user_id IS
  'Story 12.1 — reporting line. Must point to a strictly higher tier in the same tenant (enforced in the edit-user RPC, Story 12.4, not a DB CHECK).';
COMMENT ON COLUMN public.users.is_external IS
  'Story 12.1 — true for partner_agency users. Used with agency_id to sandbox external partners (FR-40).';

-- Backfill: existing users get a tier mirroring their coarse role.
UPDATE public.users
   SET role_tier = CASE
                     WHEN role = 'admin' THEN 'builder_head'::public.role_tier
                     ELSE 'front_line_rep'::public.role_tier
                   END
 WHERE role_tier IS NULL;

CREATE INDEX IF NOT EXISTS users_reports_to_idx
  ON public.users (reports_to_user_id) WHERE reports_to_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS users_agency_idx
  ON public.users (agency_id) WHERE agency_id IS NOT NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. auth_role_tier() — fine-grained tier from JWT, with role-derived fallback.
--    Zero-downtime: existing JWTs carry no role_tier claim yet (stamped by the
--    backfill-role-tier edge fn in Story 12.3) — until then, derive from role.
--    STABLE; SET search_path = '' (schema-qualify everything; auth.jwt() is fine).
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auth_role_tier()
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    (auth.jwt() -> 'app_metadata') ->> 'role_tier',
    CASE
      WHEN (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin'
      THEN 'builder_head'
      ELSE 'front_line_rep'
    END
  )
$$;

REVOKE EXECUTE ON FUNCTION public.auth_role_tier() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.auth_role_tier() TO authenticated, service_role;

COMMENT ON FUNCTION public.auth_role_tier() IS
  'Story 12.1 — fine-grained tier for the caller. Returns app_metadata.role_tier when present, else derives builder_head/front_line_rep from the role claim (zero-downtime before 12.3 stamping). Authority checks that must be precise (e.g. assignability target filter) read public.users.role_tier directly, not this helper.';

COMMIT;
