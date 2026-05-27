-- Story 1.3 review patches
-- P1: Replace raw UUID cast in user_events RLS with auth_tenant_id() helper (fail-closed)
-- P6: Revoke INSERT from authenticated — audit events written only by service_role via Edge Functions

-- P1: Recreate RLS policy using auth_tenant_id() to avoid Postgres cast exception on malformed claim
DROP POLICY IF EXISTS user_events_tenant_isolation ON public.user_events;

CREATE POLICY user_events_tenant_isolation ON public.user_events
  FOR ALL
  TO authenticated
  USING      (tenant_id = public.auth_tenant_id())
  WITH CHECK (tenant_id = public.auth_tenant_id());

-- P6: Employees must not be able to forge audit events directly
REVOKE INSERT ON public.user_events FROM authenticated;
