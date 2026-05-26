-- Story 1.1 (security hardening) — lock tenant isolation against client-side spoof
--
-- Issues caught by `mcp__supabase__get_advisors`:
--   anon_security_definer_function_executable
--   authenticated_security_definer_function_executable
--
-- Root cause: set_current_tenant(uuid) accepted any uuid. A signed-in user calling
-- POST /rest/v1/rpc/set_current_tenant could set their tenant context to a foreign
-- tenant's id, then read foreign data via PostgREST.
--
-- Two-part fix:
--   1. Policies fall back to the JWT app_metadata.tenant_id claim if the GUC is
--      not set. This lets PostgREST callers (supabase-js direct CRUD) work without
--      needing a pre-request hook to bind the GUC, while preserving the GUC path
--      for Edge Functions.
--   2. Revoke EXECUTE on set_current_tenant from authenticated + anon. Edge
--      Functions using the service-role key retain access; service-role bypasses
--      RLS anyway, but the RPC remains useful for defense-in-depth + tests.
--
-- Roll-forward only.

-- ────────────────────────────────────────────────────────────────────────────
-- Updated policies: COALESCE(GUC, JWT claim)
-- ────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS tenants_self_visible    ON public.tenants;
DROP POLICY IF EXISTS users_tenant_isolation  ON public.users;

CREATE POLICY tenants_self_visible ON public.tenants
  FOR ALL
  TO authenticated
  USING (
    id = COALESCE(
      NULLIF(current_setting('app.current_tenant', true), '')::uuid,
      ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid
    )
  )
  WITH CHECK (
    id = COALESCE(
      NULLIF(current_setting('app.current_tenant', true), '')::uuid,
      ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid
    )
  );

CREATE POLICY users_tenant_isolation ON public.users
  FOR ALL
  TO authenticated
  USING (
    tenant_id = COALESCE(
      NULLIF(current_setting('app.current_tenant', true), '')::uuid,
      ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid
    )
  )
  WITH CHECK (
    tenant_id = COALESCE(
      NULLIF(current_setting('app.current_tenant', true), '')::uuid,
      ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid
    )
  );

-- ────────────────────────────────────────────────────────────────────────────
-- Lock down set_current_tenant — service_role only
-- ────────────────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.set_current_tenant(uuid) FROM PUBLIC, anon, authenticated;
-- service_role keeps EXECUTE (granted in 0001); explicit re-grant for clarity:
GRANT  EXECUTE ON FUNCTION public.set_current_tenant(uuid) TO service_role;

COMMENT ON FUNCTION public.set_current_tenant(uuid) IS
  'Story 1.1 — binds app.current_tenant GUC for current transaction. service_role only. Edge Functions call this AFTER verifying the JWT in _shared/auth.ts and confirming the caller-supplied uuid matches the verified JWT claim. PostgREST callers do NOT need this — the RLS policy reads auth.jwt() app_metadata.tenant_id directly.';
