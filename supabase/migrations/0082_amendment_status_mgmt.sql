-- 0082_amendment_status_mgmt.sql
-- Story 16.3 (Epic 16) — FR-57. Execution team manages amendment status.
--
-- set_amendment_status — caller must be in tenant_execution_team; validates the lifecycle transition
--   (requested→acknowledged→in_progress→done, or →rejected from any non-terminal); appends an
--   immutable status_changed event.
-- add/remove_execution_member — builder_head manages membership.
-- get_amendments_for_execution — PII-MINIMIZED surface (unit_no, configuration, description, status —
--   NO lead name/phone) for execution members.
--
-- amendment_events.event_type is text → no enum change needed.
-- File-based migration; never MCP apply.

BEGIN;

-- 1. set_amendment_status -------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_amendment_status(
  p_amendment_id uuid,
  p_new_status   public.amendment_status
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_from      public.amendment_status;
  v_ok        boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_execution_team t
    WHERE t.tenant_id = v_tenant_id AND t.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'not_execution_member' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_from FROM public.amendments
  WHERE id = p_amendment_id AND tenant_id = v_tenant_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'amendment_not_found' USING ERRCODE = 'P0001';
  END IF;

  -- lifecycle: requested→acknowledged→in_progress→done; →rejected from any non-terminal
  v_ok := (v_from = 'requested'    AND p_new_status IN ('acknowledged', 'rejected'))
       OR (v_from = 'acknowledged' AND p_new_status IN ('in_progress', 'rejected'))
       OR (v_from = 'in_progress'  AND p_new_status IN ('done', 'rejected'));
  IF NOT v_ok THEN
    RAISE EXCEPTION 'invalid_transition: % -> %', v_from, p_new_status USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.amendments SET status = p_new_status WHERE id = p_amendment_id;

  PERFORM public.log_amendment_event(p_amendment_id, 'status_changed', v_from, p_new_status, NULL);

  RETURN jsonb_build_object('amendment_id', p_amendment_id, 'from', v_from, 'to', p_new_status);
END;
$$;

REVOKE ALL ON FUNCTION public.set_amendment_status(uuid, public.amendment_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_amendment_status(uuid, public.amendment_status) TO authenticated;

COMMENT ON FUNCTION public.set_amendment_status(uuid, public.amendment_status) IS
  'Story 16.3 — execution-team member moves an amendment through its lifecycle (validated transition) + appends status_changed event.';

-- 2. membership management (head-only) ------------------------------------------------------
CREATE OR REPLACE FUNCTION public.add_execution_member(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  IF public.auth_role_tier() IS DISTINCT FROM 'builder_head' THEN
    RAISE EXCEPTION 'permission_denied: builder_head only' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id AND tenant_id = v_tenant_id) THEN
    RAISE EXCEPTION 'user_not_found' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO public.tenant_execution_team (tenant_id, user_id)
  VALUES (v_tenant_id, p_user_id)
  ON CONFLICT (tenant_id, user_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_execution_member(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  IF public.auth_role_tier() IS DISTINCT FROM 'builder_head' THEN
    RAISE EXCEPTION 'permission_denied: builder_head only' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();
  DELETE FROM public.tenant_execution_team WHERE tenant_id = v_tenant_id AND user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.add_execution_member(uuid)    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_execution_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_execution_member(uuid)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_execution_member(uuid) TO authenticated;

COMMENT ON FUNCTION public.add_execution_member(uuid) IS
  'Story 16.3 — builder_head adds a user to the tenant execution team.';

-- 3. execution surface read (PII-minimized) -------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_amendments_for_execution(
  p_status public.amendment_status DEFAULT NULL
)
RETURNS TABLE (
  amendment_id  uuid,
  unit_id       uuid,
  unit_no       text,
  configuration text,
  lead_id       uuid,
  description   text,
  status        public.amendment_status,
  created_at    timestamptz,
  updated_at    timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();
  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_execution_team t
    WHERE t.tenant_id = v_tenant_id AND t.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'not_execution_member' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  -- NO lead name/phone decryption — PII minimization (AC4)
  SELECT a.id, a.unit_id, u.unit_no, u.configuration, a.lead_id, a.description, a.status, a.created_at, a.updated_at
  FROM public.amendments a
  JOIN public.units u ON u.id = a.unit_id
  WHERE a.tenant_id = v_tenant_id
    AND (p_status IS NULL OR a.status = p_status)
  ORDER BY a.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_amendments_for_execution(public.amendment_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_amendments_for_execution(public.amendment_status) TO authenticated;

COMMENT ON FUNCTION public.get_amendments_for_execution(public.amendment_status) IS
  'Story 16.3 — execution-team surface: amendments with unit_no/configuration/description/status only (NO lead PII). Member-gated.';

COMMIT;
