-- Story 2.2 (security patch 2) — Explicit revoke anon on log_timeline_event
-- Supabase auto-grants EXECUTE to anon role on public functions.
-- REVOKE FROM PUBLIC is insufficient — must revoke from anon explicitly.
--
-- Roll-forward only. Never edit after apply.

REVOKE EXECUTE ON FUNCTION public.log_timeline_event(uuid, public.timeline_event_type, jsonb)
  FROM anon;
