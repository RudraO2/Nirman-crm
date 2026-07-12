-- 0112_quiet_expiry_releases.sql
-- Push-noise guard (practicality backlog P0, 2026-07-12).
--
-- Every cron-expired hold emitted inventory_changed kind='release', and the
-- 16.4 dispatcher pushed it to the WHOLE internal team — a busy project would
-- train reps to disable notifications, killing the valuable follow-up alarms.
--
-- Fix at the producer: release_expired_holds() now emits kind='release_expired'
-- (body otherwise identical to 0077). The dispatcher claims-but-mutes that kind,
-- so the event stream stays complete for future consumers while nobody is
-- pinged for routine expiry churn. Deliberate, human-initiated availability
-- changes keep pushing: kind='release' (head force-release, 0074/0084/0104) and
-- kind='new_stock' (restock). No mobile/web consumer reads these kinds directly
-- (checked: zero references outside supabase/).
-- File-based migration; never MCP apply.

BEGIN;

CREATE OR REPLACE FUNCTION public.release_expired_holds()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_h     RECORD;
  v_count int := 0;
BEGIN
  FOR v_h IN
    SELECT id, unit_id, lead_id, tenant_id
    FROM   public.unit_holds
    WHERE  released_at IS NULL
      AND  expires_at <= now()
    ORDER BY expires_at
    LIMIT 500
    FOR UPDATE SKIP LOCKED
  LOOP
    -- TOCTOU re-assert: only release if STILL active + STILL expired
    UPDATE public.unit_holds
       SET released_at = now(), outcome = 'expired'
     WHERE id = v_h.id AND released_at IS NULL AND expires_at <= now();
    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    -- return the unit to the pool (only if it is still on hold)
    UPDATE public.units
       SET status = 'available', status_version = status_version + 1
     WHERE id = v_h.unit_id AND status = 'hold';

    -- system timeline + domain event (no JWT here → direct insert, actor_role='system')
    INSERT INTO public.lead_timeline (tenant_id, lead_id, actor_user_id, actor_role, event_type, payload, occurred_at)
    VALUES (v_h.tenant_id, v_h.lead_id, NULL, 'system', 'hold_expired',
            jsonb_build_object('unit_id', v_h.unit_id, 'hold_id', v_h.id), now());

    INSERT INTO public.domain_events (tenant_id, event_type, payload, occurred_at)
    VALUES (v_h.tenant_id, 'hold_expired',
            jsonb_build_object('lead_id', v_h.lead_id, 'unit_id', v_h.unit_id, 'hold_id', v_h.id), now());

    -- 0112: routine expiry churn is 'release_expired' — the dispatcher mutes it.
    -- Human-initiated availability changes keep the pushy 'release'/'new_stock'.
    PERFORM public.emit_inventory_changed(v_h.unit_id, 'release_expired');

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.release_expired_holds() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_expired_holds() TO service_role;

COMMENT ON FUNCTION public.release_expired_holds() IS
  'Story 15.3 + 0112 — pg_cron sweep. Releases expired active holds (TOCTOU-safe), returns unit to available, logs hold_expired. Emits inventory_changed kind=release_expired (muted by the 16.4 dispatcher — routine churn must not push-spam the team). Returns count released.';

COMMIT;
