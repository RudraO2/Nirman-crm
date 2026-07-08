-- 0083_amendment_notify.sql
-- Story 16.4 (Epic 16) — FR-57. Auto-notify on amendment log + on status change.
--
-- NOTE (same as 14.4): there is no "pending_notifications" table; the real transport is domain_events
-- + a per-event FCM edge fn → device_tokens. Producers are TRIGGERS on amendments (so the 16.2/16.3
-- RPCs stay untouched): AFTER INSERT → 'amendment_logged'; AFTER UPDATE OF status → 'amendment_status_changed'.
-- Trigger fns are SECURITY DEFINER (authenticated has no INSERT on domain_events). Payloads carry only
-- unit/lead/amendment IDs + status — NO PII (AC3).
--
-- get_amendment_log_audience(amendment) → execution-team user_ids (for the "logged" notification).
-- The "status_changed" notification targets amendments.logged_by (the originating agent) — the edge
-- fn reads that directly. send-amendment-notification edge fn fans out FCM (deferred deploy).
--
-- File-based migration; never MCP apply.

BEGIN;

-- 1. producer triggers ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.amendments_notify_logged()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  INSERT INTO public.domain_events (tenant_id, event_type, payload, occurred_at)
  VALUES (NEW.tenant_id, 'amendment_logged',
          jsonb_build_object('amendment_id', NEW.id, 'unit_id', NEW.unit_id, 'lead_id', NEW.lead_id, 'kind', 'logged'),
          now());
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.amendments_notify_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.domain_events (tenant_id, event_type, payload, occurred_at)
    VALUES (NEW.tenant_id, 'amendment_status_changed',
            jsonb_build_object('amendment_id', NEW.id, 'unit_id', NEW.unit_id, 'lead_id', NEW.lead_id,
                               'to_status', NEW.status, 'notify_user_id', NEW.logged_by, 'kind', 'status_changed'),
            now());
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS amendments_notify_logged_trg ON public.amendments;
CREATE TRIGGER amendments_notify_logged_trg
  AFTER INSERT ON public.amendments
  FOR EACH ROW EXECUTE FUNCTION public.amendments_notify_logged();

DROP TRIGGER IF EXISTS amendments_notify_status_trg ON public.amendments;
CREATE TRIGGER amendments_notify_status_trg
  AFTER UPDATE OF status ON public.amendments
  FOR EACH ROW EXECUTE FUNCTION public.amendments_notify_status();

-- 2. audience resolver (execution team) -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_amendment_log_audience(p_amendment_id uuid)
RETURNS TABLE (user_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  SELECT tenant_id INTO v_tenant_id FROM public.amendments WHERE id = p_amendment_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT t.user_id
    FROM public.tenant_execution_team t
    JOIN public.users u ON u.id = t.user_id AND u.is_active = true
    WHERE t.tenant_id = v_tenant_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_amendment_log_audience(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_amendment_log_audience(uuid) TO service_role;

COMMENT ON FUNCTION public.get_amendment_log_audience(uuid) IS
  'Story 16.4 — execution-team recipient user_ids for an amendment "logged" notification. Consumed by send-amendment-notification (service_role).';

COMMIT;
