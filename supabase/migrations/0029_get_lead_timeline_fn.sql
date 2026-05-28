-- Story 2.2 / FR-19 — get_lead_timeline RPC for detail screen
-- Returns chronological event log for one lead with actor name joined from public.users.
-- Ownership-checked: returns 0 rows if lead not visible to caller.
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.get_lead_timeline(p_lead_id uuid)
RETURNS TABLE (
  id            uuid,
  event_type    text,
  actor_user_id uuid,
  actor_role    text,
  actor_name    text,
  payload       jsonb,
  occurred_at   timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Ownership gate — silently return 0 rows if lead is not assigned to caller
  IF NOT EXISTS (
    SELECT 1 FROM public.leads l
    WHERE l.id = p_lead_id AND l.assigned_to_user_id = v_user_id
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    t.id,
    t.event_type::text,
    t.actor_user_id,
    t.actor_role,
    u.email_or_username AS actor_name,
    t.payload,
    t.occurred_at
  FROM public.lead_timeline t
  LEFT JOIN public.users u ON u.id = t.actor_user_id
  WHERE t.lead_id = p_lead_id
  ORDER BY t.occurred_at DESC
  LIMIT 200;
END;
$$;

COMMENT ON FUNCTION public.get_lead_timeline(uuid) IS
  'Story 2.2 — Returns chronological timeline events for one owned lead. SECURITY DEFINER; ownership-checked.';

REVOKE EXECUTE ON FUNCTION public.get_lead_timeline(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_lead_timeline(uuid) TO authenticated;
