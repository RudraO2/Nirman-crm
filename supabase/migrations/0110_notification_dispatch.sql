-- 0110_notification_dispatch.sql
-- Story 16.4 — FCM push delivery for builder-ops domain events.
--
-- The producers have been live since 0074/0077/0083 (inventory_changed,
-- hold_expiring, amendment_logged, amendment_status_changed, developer_update_posted
-- rows in domain_events) and the fan-out fns (send-amendment-notification,
-- send-developer-update) are deployed — but NOTHING drained the queue, so no
-- push was ever sent. This adds the drain:
--   * domain_events.dispatched_at + partial index — the queue marker.
--   * claim_domain_events(types, limit) — atomic FOR UPDATE SKIP LOCKED claim
--     (service_role only), so overlapping cron ticks never double-send.
--   * get_inventory_event_audience(unit_id) — internal team + partners whose
--     agency is shared to the unit's project (mirror of the 0073 audience fn;
--     0074's promise: "fans out FCM honouring partner visibility, no margin").
--   * pg_cron job (every minute) posting to the new dispatch-notifications edge
--     fn with the 0087 cron-secret pattern.
-- Historical backlog is left undispatched on purpose: the claim only considers
-- events younger than 1 day, so enabling this does not blast weeks-old pushes.
-- File-based migration; never MCP apply.

BEGIN;

ALTER TABLE public.domain_events ADD COLUMN IF NOT EXISTS dispatched_at timestamptz;

CREATE INDEX IF NOT EXISTS domain_events_undispatched_idx
  ON public.domain_events (occurred_at)
  WHERE dispatched_at IS NULL;

-- ── claim_domain_events ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.claim_domain_events(p_types text[], p_limit int DEFAULT 50)
RETURNS SETOF public.domain_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.domain_events d
     SET dispatched_at = now()
   WHERE d.id IN (
     SELECT e.id
     FROM public.domain_events e
     WHERE e.dispatched_at IS NULL
       AND e.event_type = ANY (p_types)
       AND e.occurred_at > now() - interval '1 day'
     ORDER BY e.occurred_at
     LIMIT greatest(1, least(coalesce(p_limit, 50), 200))
     FOR UPDATE SKIP LOCKED
   )
   RETURNING d.*;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_domain_events(text[], int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_domain_events(text[], int) TO service_role;

COMMENT ON FUNCTION public.claim_domain_events(text[], int) IS
  'Story 16.4 — atomically claims (dispatched_at=now) up to N undispatched domain_events of the given types, ≤1 day old, FOR UPDATE SKIP LOCKED. Consumed by the dispatch-notifications edge fn (service_role). At-most-once: failed sends are logged, not re-queued.';

-- ── get_inventory_event_audience ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_inventory_event_audience(p_unit_id uuid)
RETURNS TABLE (user_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id  uuid;
  v_project_id uuid;
BEGIN
  SELECT u.tenant_id, u.project_id INTO v_tenant_id, v_project_id
  FROM public.units u WHERE u.id = p_unit_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  RETURN QUERY
  -- internal sales team (everyone non-external in the tenant)
  SELECT u.id
  FROM public.users u
  WHERE u.tenant_id = v_tenant_id
    AND u.is_active = true
    AND COALESCE(u.is_external, false) = false
  UNION
  -- partner agency users — only when their agency is shared to the unit's project
  SELECT u.id
  FROM public.users u
  JOIN public.agency_projects ap
    ON ap.agency_id = u.agency_id
   AND ap.tenant_id = v_tenant_id
   AND ap.project_id = v_project_id
  WHERE u.tenant_id = v_tenant_id
    AND u.is_active = true
    AND u.role_tier = 'partner_agency';
END;
$$;

REVOKE ALL ON FUNCTION public.get_inventory_event_audience(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_inventory_event_audience(uuid) TO service_role;

COMMENT ON FUNCTION public.get_inventory_event_audience(uuid) IS
  'Story 16.4 — recipient user_ids for an inventory_changed event on a unit: internal team always; partner_agency users only if agency-shared to the project (0073 audience pattern). Consumed by dispatch-notifications (service_role).';

-- ── cron: drain every minute (0087 secret pattern) ───────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'dispatch-notifications',
      '* * * * *',
      $cron$
        SELECT net.http_post(
          url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1)
                     || '/functions/v1/dispatch-notifications',
          headers := jsonb_build_object(
            'Content-Type',   'application/json',
            'Authorization',  'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1),
            'x-cron-secret',  (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret' LIMIT 1)
          ),
          body    := '{}'::jsonb
        );
      $cron$
    );
  END IF;
END $$;

COMMIT;
