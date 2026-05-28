-- Story 4.6 code-review patches (P1 security fixes for reactivate_future_leads)
-- P1-A: Add auth.uid() IS NULL guard (missing from 0046, inconsistent with other fns).
-- P1-B: Add v_employee_id IS NULL guard before calling assign_lead.
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.reactivate_future_leads(
  p_leads jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor_id    uuid := auth.uid();
  v_actor_role  text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id   uuid := public.auth_tenant_id();
  v_entry       jsonb;
  v_lead_id     uuid;
  v_employee_id uuid;
  v_affected    int;
  v_count       int := 0;
BEGIN
  -- P1-A: Require authenticated caller (consistent with all other RPCs in this codebase)
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF v_actor_role <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'tenant_missing' USING ERRCODE = '42501';
  END IF;

  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_leads)
  LOOP
    v_lead_id     := (v_entry ->> 'lead_id')::uuid;
    v_employee_id := (v_entry ->> 'employee_id')::uuid;

    -- P1-B: Reject null employee_id before touching any lead rows
    IF v_employee_id IS NULL THEN
      RAISE EXCEPTION 'employee_id_required for lead: %', v_lead_id;
    END IF;

    UPDATE public.leads
       SET status     = 'warm',
           updated_at = now()
     WHERE id         = v_lead_id
       AND tenant_id  = v_tenant_id
       AND status     = 'future';

    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected = 0 THEN
      RAISE EXCEPTION 'lead_not_found_or_not_future: %', v_lead_id;
    END IF;

    PERFORM public.log_timeline_event(
      v_lead_id,
      'status_changed'::public.timeline_event_type,
      jsonb_build_object('from', 'future', 'to', 'warm', 'restored', true)
    );

    PERFORM public.assign_lead(v_lead_id, v_employee_id, NULL::timestamptz);

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('reactivated', v_count);
END;
$$;

COMMENT ON FUNCTION public.reactivate_future_leads(jsonb) IS
  'Story 4.6 (patched 0047) — Bulk reactivate future leads. auth.uid() guard added (P1-A). '
  'employee_id null guard added (P1-B). Sets status=warm, logs status_changed(restored=true), '
  'then calls assign_lead per entry. Raises on any per-lead failure.';

REVOKE EXECUTE ON FUNCTION public.reactivate_future_leads(jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.reactivate_future_leads(jsonb) TO authenticated;
