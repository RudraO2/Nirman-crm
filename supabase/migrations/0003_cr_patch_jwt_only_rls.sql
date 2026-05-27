-- Story 1.1 (CR patch 2026-05-26) — JWT-only RLS; split tenants/users policies by operation
--
-- Findings resolved:
--   F2: Drop GUC branch from COALESCE. No legitimate code sets app.current_tenant after
--       auth.ts RPC removal. GUC was a spoof vector: any authenticated user could call
--       SELECT set_config('app.current_tenant', '<foreign-uuid>', true) then read foreign rows.
--   F3: tenants_self_visible FOR ALL → FOR SELECT. Authenticated must not mutate tenants.
--   F4: users_tenant_isolation FOR ALL → split: SELECT (all in tenant), DML (admin only).
--
-- auth_tenant_id() helper: safely extracts tenant UUID from JWT with UUID format guard.
-- Malformed UUID strings return NULL → all RLS comparisons false → zero rows (fail-closed).
--
-- Roll-forward only. Do not edit after first apply.

-- ────────────────────────────────────────────────────────────────────────────
-- Helper: extract tenant UUID from JWT with format guard
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auth_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN (auth.jwt() -> 'app_metadata') ->> 'tenant_id'
           ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    THEN ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid
    ELSE NULL
  END
$$;

REVOKE EXECUTE ON FUNCTION public.auth_tenant_id() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.auth_tenant_id() TO authenticated, service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- Tenants: SELECT-only for authenticated (F3)
-- ────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS tenants_self_visible ON public.tenants;

CREATE POLICY tenants_self_visible ON public.tenants
  FOR SELECT
  TO authenticated
  USING (id = public.auth_tenant_id());

-- ────────────────────────────────────────────────────────────────────────────
-- Users: SELECT for all in tenant; DML admin-only (F2 + F4)
-- ────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS users_tenant_isolation ON public.users;

CREATE POLICY users_select ON public.users
  FOR SELECT
  TO authenticated
  USING (tenant_id = public.auth_tenant_id());

CREATE POLICY users_admin_insert ON public.users
  FOR INSERT
  TO authenticated
  WITH CHECK (
    tenant_id = public.auth_tenant_id()
    AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin'
  );

CREATE POLICY users_admin_update ON public.users
  FOR UPDATE
  TO authenticated
  USING (
    tenant_id = public.auth_tenant_id()
    AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin'
  )
  WITH CHECK (
    tenant_id = public.auth_tenant_id()
    AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin'
  );

CREATE POLICY users_admin_delete ON public.users
  FOR DELETE
  TO authenticated
  USING (
    tenant_id = public.auth_tenant_id()
    AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin'
  );
