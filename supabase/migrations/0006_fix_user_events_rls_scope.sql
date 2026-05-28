-- Story 1.3 review patch round 2
-- P2: Narrow user_events RLS policy from FOR ALL to FOR SELECT
-- After migration 0005 revoked INSERT from authenticated, FOR ALL is misleadingly broad.
-- Only SELECT is exercisable by authenticated; service_role (Edge Functions) handles writes.

DROP POLICY IF EXISTS user_events_tenant_isolation ON public.user_events;

CREATE POLICY user_events_tenant_isolation ON public.user_events
  FOR SELECT
  TO authenticated
  USING (tenant_id = public.auth_tenant_id());
