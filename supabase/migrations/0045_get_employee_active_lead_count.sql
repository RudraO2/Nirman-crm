-- Story 4.5 — get_employee_active_lead_count
-- Admin-only RPC to count active (non-Archived) leads for an employee.
-- Used by EmployeeActions to gate deactivation before showing the reassignment modal.
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.get_employee_active_lead_count(
  p_employee_id uuid
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor_role  text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id   uuid := public.auth_tenant_id();
  v_count       int;
BEGIN
  IF v_actor_role <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  -- Validate employee belongs to caller's tenant with role='employee'
  IF NOT EXISTS (
    SELECT 1 FROM public.users
     WHERE id        = p_employee_id
       AND tenant_id = v_tenant_id
       AND role      = 'employee'
  ) THEN
    RAISE EXCEPTION 'employee_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT COUNT(*)::int
    INTO v_count
    FROM public.leads
   WHERE assigned_to_user_id = p_employee_id
     AND tenant_id           = v_tenant_id
     AND status NOT IN ('dead', 'sold', 'future');

  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_employee_active_lead_count(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_employee_active_lead_count(uuid) TO authenticated;
