-- Story 2.2 (security patch) — Revoke anon execute on log_timeline_event
-- Supabase security advisor finding: anon_security_definer_function_executable
-- Default PostgreSQL PUBLIC grant allows anon role to call SECURITY DEFINER functions.
-- log_timeline_event must only be callable by authenticated users.
--
-- Roll-forward only. Never edit after apply.

REVOKE EXECUTE ON FUNCTION public.log_timeline_event(uuid, public.timeline_event_type, jsonb)
  FROM PUBLIC;

-- Re-grant explicitly to authenticated only
GRANT EXECUTE ON FUNCTION public.log_timeline_event(uuid, public.timeline_event_type, jsonb)
  TO authenticated;
