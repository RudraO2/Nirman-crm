-- Story 4.2 — Admin bulk-assigns leads with equal distribution.
-- Adds: bulk_assign_leads RPC, get_employee_active_lead_counts RPC.
-- bulk_assign_leads calls the existing assign_lead() per pair, reusing all
-- validation + timeline + cascade-share-revoke logic from 0038/0039.
-- Roll-forward only. Never edit after apply.

-- ── 1. bulk_assign_leads(p_assignments jsonb, p_deadline timestamptz) ─────────
CREATE OR REPLACE FUNCTION public.bulk_assign_leads(
  p_assignments jsonb,
  p_deadline    timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_item       jsonb;
  v_lead_id    uuid;
  v_user_id    uuid;
  v_assigned   int  := 0;
  v_per_emp    jsonb := '{}'::jsonb;
  v_prev_count int;
BEGIN
  IF v_actor_role <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF p_assignments IS NULL OR jsonb_typeof(p_assignments) <> 'array' THEN
    RAISE EXCEPTION 'invalid_assignments' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_assignments) = 0 THEN
    RAISE EXCEPTION 'empty_assignments' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_assignments) > 500 THEN
    RAISE EXCEPTION 'too_many_assignments' USING ERRCODE = '22023';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_assignments) LOOP
    v_lead_id := (v_item->>'lead_id')::uuid;
    v_user_id := (v_item->>'target_user_id')::uuid;

    IF v_lead_id IS NULL OR v_user_id IS NULL THEN
      RAISE EXCEPTION 'malformed_assignment_item' USING ERRCODE = '22023';
    END IF;

    -- Delegate to assign_lead — handles auth check, timeline, cascade-revoke.
    -- assign_lead re-reads auth.uid()/auth.jwt() which remain valid in this session.
    PERFORM public.assign_lead(v_lead_id, v_user_id, p_deadline);
    v_assigned := v_assigned + 1;

    -- Accumulate per-employee count for notification fan-out.
    v_prev_count := COALESCE((v_per_emp->>(v_user_id::text))::int, 0);
    v_per_emp    := jsonb_set(v_per_emp, ARRAY[v_user_id::text], to_jsonb(v_prev_count + 1));
  END LOOP;

  RETURN jsonb_build_object(
    'assigned',      v_assigned,
    'per_employee',  v_per_emp
  );
END;
$$;

COMMENT ON FUNCTION public.bulk_assign_leads(jsonb, timestamptz) IS
  'Story 4.2 — Admin-only bulk assign. Calls assign_lead() per pair; max 500 items. Returns {assigned, per_employee: {user_id: count}}.';

REVOKE EXECUTE ON FUNCTION public.bulk_assign_leads(jsonb, timestamptz) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.bulk_assign_leads(jsonb, timestamptz) TO authenticated;

-- ── 2. get_employee_active_lead_counts(p_user_ids uuid[]) ────────────────────
CREATE OR REPLACE FUNCTION public.get_employee_active_lead_counts(
  p_user_ids uuid[]
)
RETURNS TABLE (user_id uuid, active_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
BEGIN
  IF v_actor_role <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF p_user_ids IS NULL OR array_length(p_user_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT l.assigned_to_user_id AS user_id,
         count(*)::bigint       AS active_count
    FROM public.leads l
   WHERE l.tenant_id             = v_tenant_id
     AND l.assigned_to_user_id   = ANY(p_user_ids)
     AND l.status::text         IN ('hot', 'warm', 'cold')
   GROUP BY l.assigned_to_user_id;
END;
$$;

COMMENT ON FUNCTION public.get_employee_active_lead_counts(uuid[]) IS
  'Story 4.2 — Admin-only. Returns active (hot/warm/cold) lead count per employee for warning-banner logic.';

REVOKE EXECUTE ON FUNCTION public.get_employee_active_lead_counts(uuid[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_employee_active_lead_counts(uuid[]) TO authenticated;
