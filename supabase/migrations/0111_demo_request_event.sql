-- 0111_demo_request_event.sql
-- Story 8.5 (first consumer) — emit a domain_event when a demo request lands so
-- the 16.4 dispatcher can alert the founder instantly (push today, email once
-- RESEND_API_KEY is set). Without this, captured prospects sat unseen until
-- someone opened the ops console.
--
-- demo_requests has no tenant; domain_events.tenant_id is NOT NULL, so the
-- event is filed under the seed platform tenant (same convention would apply
-- to any future platform-level event). Payload carries the request id ONLY —
-- no email address travels through the events table.
-- File-based migration; never MCP apply.

BEGIN;

CREATE OR REPLACE FUNCTION public._notify_demo_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  INSERT INTO public.domain_events (tenant_id, event_type, payload, occurred_at)
  VALUES ('00000000-0000-0000-0000-000000000001', 'demo_request_created',
          jsonb_build_object('demo_request_id', NEW.id, 'source', NEW.source), now());
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._notify_demo_request() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS demo_requests_notify ON public.demo_requests;
CREATE TRIGGER demo_requests_notify
  AFTER INSERT ON public.demo_requests
  FOR EACH ROW EXECUTE FUNCTION public._notify_demo_request();

COMMENT ON FUNCTION public._notify_demo_request() IS
  'Story 8.5 — files a demo_request_created domain_event (id only, no PII) for the dispatch-notifications drain to alert the founder.';

COMMIT;
