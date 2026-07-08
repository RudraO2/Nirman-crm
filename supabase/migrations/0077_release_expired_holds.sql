-- 0077_release_expired_holds.sql
-- Story 15.3 (Epic 15) — FR-52/FR-53. Auto-release expired holds + expiry warning via pg_cron.
--
-- System maintenance functions — run by pg_cron with NO JWT, so they are NOT tenant-scoped and do
-- NOT use auth_tenant_id()/log_timeline_event (which require JWT). They write lead_timeline +
-- domain_events DIRECTLY with actor_role='system' (the mark_overdue_followups pattern, 0026).
--
-- release_expired_holds() — TOCTOU-safe sweep:
--   • SELECT expired active holds FOR UPDATE SKIP LOCKED LIMIT 500 (bounded; concurrent ticks safe).
--   • Per row, RE-ASSERT the predicate inside the UPDATE (released_at IS NULL AND expires_at <= now()),
--     so a hold confirmed/released a moment earlier is NOT blind-released (IF NOT FOUND → CONTINUE).
--   • Same txn: unit hold→available (only if still 'hold'); log hold_expired; emit inventory_changed.
-- warn_expiring_holds() — enqueues a hold_expiring domain_event ~T-2h before expiry, once per hold
--   (dedup via unit_holds.expiry_warned_at). FCM dispatch is a deferred edge fn.
--
-- 'hold_expired' added to timeline_event_type (bare ADD VALUE before BEGIN; used only at call time).
-- File-based migration; never MCP apply.

ALTER TYPE public.timeline_event_type ADD VALUE IF NOT EXISTS 'hold_expired';

BEGIN;

ALTER TABLE public.unit_holds
  ADD COLUMN IF NOT EXISTS expiry_warned_at timestamptz;

-- 1. release_expired_holds -------------------------------------------------------------------
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

    -- reuse the 14.5 producer so the sales team is notified the unit is free again
    PERFORM public.emit_inventory_changed(v_h.unit_id, 'release');

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.release_expired_holds() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_expired_holds() TO service_role;

COMMENT ON FUNCTION public.release_expired_holds() IS
  'Story 15.3 — pg_cron sweep. Releases expired active holds (FOR UPDATE SKIP LOCKED LIMIT 500, TOCTOU-safe re-assert), returns unit to available, logs hold_expired, notifies. System fn (no JWT). Returns count released.';

-- 2. warn_expiring_holds ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.warn_expiring_holds()
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
    SELECT id, unit_id, lead_id, tenant_id, holding_agent_id, expires_at
    FROM   public.unit_holds
    WHERE  released_at IS NULL
      AND  expiry_warned_at IS NULL
      AND  expires_at > now()
      AND  expires_at <= now() + interval '2 hours'
    ORDER BY expires_at
    LIMIT 500
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.unit_holds SET expiry_warned_at = now()
     WHERE id = v_h.id AND expiry_warned_at IS NULL;
    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    INSERT INTO public.domain_events (tenant_id, event_type, payload, occurred_at)
    VALUES (v_h.tenant_id, 'hold_expiring',
            jsonb_build_object('lead_id', v_h.lead_id, 'unit_id', v_h.unit_id, 'hold_id', v_h.id,
                               'holding_agent_id', v_h.holding_agent_id, 'expires_at', v_h.expires_at), now());

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.warn_expiring_holds() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.warn_expiring_holds() TO service_role;

COMMENT ON FUNCTION public.warn_expiring_holds() IS
  'Story 15.3 — pg_cron. Emits hold_expiring domain_event ~T-2h before expiry, once per hold (dedup via expiry_warned_at). System fn. Returns count warned.';

-- 3. pg_cron schedules (guarded; pg_cron present on prod, absent locally) --------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('release-expired-holds', '* * * * *', $cron$ SELECT public.release_expired_holds(); $cron$);
    PERFORM cron.schedule('warn-expiring-holds',  '*/5 * * * *', $cron$ SELECT public.warn_expiring_holds(); $cron$);
  END IF;
END $$;

COMMIT;
