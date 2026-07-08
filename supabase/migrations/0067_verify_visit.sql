-- 0067_verify_visit.sql
-- Story 13.4 (Epic 13) — FR-44/FR-46. Reception verifies a physical visit by customer code.
--
-- verify_visit(code): receptionist (or builder_head) resolves a customer_code to a lead in the
-- caller's tenant, increments visit_count, and logs visit_verified + visit_logged Timeline
-- events with the new ordinal. SECURITY DEFINER (owner) so it can mutate regardless of the
-- gate-only receptionist's access; the timeline actor is still the receptionist (auth.uid()).
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

CREATE OR REPLACE FUNCTION public.verify_visit(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_tenant_id uuid := public.auth_tenant_id();
  v_actor_id  uuid := auth.uid();
  v_tier      text := public.auth_role_tier();
  v_lead_id   uuid;
  v_new_count int;
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF v_tier NOT IN ('receptionist', 'builder_head') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'tenant_missing' USING ERRCODE = '42501';
  END IF;
  IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
    RAISE EXCEPTION 'invalid_customer_code' USING ERRCODE = 'P0002';
  END IF;

  SELECT id INTO v_lead_id
    FROM public.leads
   WHERE tenant_id = v_tenant_id
     AND customer_code = upper(trim(p_code))
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_customer_code' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.leads
     SET visit_count    = visit_count + 1,
         last_action_at = now(),
         updated_at     = now()
   WHERE id = v_lead_id
   RETURNING visit_count INTO v_new_count;

  PERFORM public.log_timeline_event(
    v_lead_id, 'visit_verified'::public.timeline_event_type,
    jsonb_build_object('visit_ordinal', v_new_count)
  );
  PERFORM public.log_timeline_event(
    v_lead_id, 'visit_logged'::public.timeline_event_type,
    jsonb_build_object('visit_ordinal', v_new_count)
  );

  RETURN jsonb_build_object('lead_id', v_lead_id, 'visit_count', v_new_count);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.verify_visit(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.verify_visit(text) TO authenticated;

COMMENT ON FUNCTION public.verify_visit(text) IS
  'Story 13.4 — receptionist/builder_head verifies a visit by customer_code: increments visit_count, logs visit_verified + visit_logged with the new ordinal. Invalid/unknown/wrong-tenant code → invalid_customer_code.';

COMMIT;
