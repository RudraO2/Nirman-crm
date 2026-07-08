-- 0056_tenant_lifecycle_status.sql
-- Story 8.2 (Epic 8) — Architecture Decision 37 (Tenant lifecycle status + 14-day trial).
--
-- Adds tenant lifecycle state so access can be gated on active/trial and later
-- tied to billing (D8 seam lands separately in 0058). Two parts:
--   1. Schema: tenants.status (enum) + tenants.trial_ends_at; new tenants default
--      to a 14-day trial; the existing V1 tenant(s) back-filled to 'active'.
--   2. Gate: redefine public.auth_tenant_id() to fail-closed when the caller's
--      tenant is not in ('trial','active'). This is the SINGLE chokepoint —
--      every tenant-scoped RLS policy and every SECURITY DEFINER RPC already
--      compares `tenant_id = public.auth_tenant_id()`, so returning NULL for a
--      suspended/cancelled tenant denies ALL data at the data layer with no
--      per-policy edits. SECURITY DEFINER (owner has BYPASSRLS) prevents the
--      tenants_self_visible RLS policy (which calls auth_tenant_id) from
--      recursing when the function reads public.tenants.
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

-- 1. Lifecycle status enum (mirrors codebase enum convention: user_role, lead_status)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tenant_status') THEN
    CREATE TYPE public.tenant_status AS ENUM ('trial', 'active', 'suspended', 'cancelled');
  END IF;
END $$;

-- 2. New columns. Column defaults give AC2: an INSERT naming neither column yields
--    a 14-day trial. trial_ends_at stays nullable so active/back-filled tenants hold NULL.
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS status        public.tenant_status NOT NULL DEFAULT 'trial',
  ADD COLUMN IF NOT EXISTS trial_ends_at timestamptz          DEFAULT (now() + interval '14 days');

COMMENT ON COLUMN public.tenants.status IS
  'Story 8.2 / Decision 37 — lifecycle state. Access gated on status IN (trial,active) via auth_tenant_id().';
COMMENT ON COLUMN public.tenants.trial_ends_at IS
  'Story 8.2 / Decision 37 — trial window end. NULL for active (non-trial) tenants. Trial-end behavior (soft lock) is an open product decision; no auto-suspend in 8.2.';

-- 3. Back-fill existing V1 tenant(s) → active. At apply time the only rows are the
--    pre-existing production tenant(s); new tenants are created later by
--    signup-create-tenant (8.3) which explicitly sets status='trial'.
UPDATE public.tenants
   SET status = 'active', trial_ends_at = NULL;

-- 4. Fail-closed status gate via the auth_tenant_id() chokepoint.
--    Returns the JWT tenant uuid ONLY when that tenant exists and is trial/active;
--    NULL otherwise (malformed claim, missing tenant, or suspended/cancelled).
--    SECURITY DEFINER: function owner bypasses RLS, so the internal read of
--    public.tenants does NOT re-trigger tenants_self_visible (no recursion).
--    UUID format guard preserved verbatim from 0003 (fail-closed on malformed claim).
CREATE OR REPLACE FUNCTION public.auth_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT t.id
  FROM public.tenants t
  WHERE t.id = (
    CASE
      WHEN (auth.jwt() -> 'app_metadata') ->> 'tenant_id'
             ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      THEN ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid
      ELSE NULL
    END
  )
  AND t.status IN ('trial', 'active')
$$;

-- Preserve grants exactly as 0003 set them.
REVOKE EXECUTE ON FUNCTION public.auth_tenant_id() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.auth_tenant_id() TO authenticated, service_role;

COMMENT ON FUNCTION public.auth_tenant_id() IS
  'JWT-derived tenant id, fail-closed. Returns tenant uuid only when app_metadata.tenant_id is a valid UUID AND the tenant status IN (trial,active); else NULL. SECURITY DEFINER to read tenants without RLS recursion (Story 8.2 / Decision 37; supersedes 0003 JWT-only form).';

COMMIT;
