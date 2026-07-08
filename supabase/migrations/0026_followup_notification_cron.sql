-- Story 3.6 + 3.7 — pg_cron jobs for follow-up reminders and overdue flagging
--
-- Prerequisites (one-time, Supabase dashboard):
--   1. Enable pg_cron extension:     Database → Extensions → pg_cron
--   2. Enable pg_net extension:      Database → Extensions → pg_net
--   3. Store service role key:       SELECT vault.create_secret('service_role_key', '<YOUR_SERVICE_ROLE_KEY>');
--   4. Deploy Edge Functions:
--        supabase functions deploy send-followup-notifications
--        supabase functions deploy process-overdue-followups
--
-- Roll-forward only. Never edit after apply.

-- ── mark_overdue_followups ────────────────────────────────────────────────────
-- Logs followup_overdue timeline event for leads that are 15+ min past due
-- with no qualifying action logged since next_followup_at.
-- Called by pg_cron every 5 minutes (or via Edge Function).

CREATE OR REPLACE FUNCTION public.mark_overdue_followups()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_lead    RECORD;
  v_count   int := 0;
BEGIN
  FOR v_lead IN
    SELECT l.id, l.tenant_id, l.assigned_to_user_id
      FROM public.leads l
     WHERE l.next_followup_at IS NOT NULL
       AND l.next_followup_at < now() - interval '15 minutes'
       AND l.next_followup_at > now() - interval '25 hours'  -- cap to avoid re-processing old leads
       AND l.status NOT IN ('dead', 'sold')
       AND NOT EXISTS (
         SELECT 1 FROM public.lead_timeline t
          WHERE t.lead_id = l.id
            AND t.event_type IN (
                  'status_changed', 'remark_added', 'followup_rescheduled',
                  'call_initiated', 'whatsapp_sent', 'visit_rescheduled',
                  'followup_overdue'
                )
            AND t.occurred_at >= l.next_followup_at
       )
  LOOP
    -- Insert system timeline event (actor = NULL = system)
    INSERT INTO public.lead_timeline (
      tenant_id, lead_id, actor_user_id, actor_role, event_type, payload, occurred_at
    ) VALUES (
      v_lead.tenant_id,
      v_lead.id,
      NULL,
      'system',
      'followup_overdue',
      '{}'::jsonb,
      now()
    );
    -- Also write domain_events
    INSERT INTO public.domain_events (tenant_id, event_type, payload, occurred_at)
    VALUES (
      v_lead.tenant_id,
      'followup_overdue',
      jsonb_build_object('lead_id', v_lead.id, 'assigned_to_user_id', v_lead.assigned_to_user_id),
      now()
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.mark_overdue_followups() IS
  'Story 3.7 — Logs followup_overdue timeline events for leads 15+ min past due with no action. Returns count flagged. Called by pg_cron every 5 min.';

REVOKE EXECUTE ON FUNCTION public.mark_overdue_followups() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.mark_overdue_followups() TO   service_role;

-- ── pg_cron jobs (requires pg_cron + pg_net extensions enabled) ───────────────

DO $$
BEGIN
  -- Only schedule if pg_cron extension is available
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN

    -- Send follow-up reminder notifications every minute
    -- Edge Function queries leads with next_followup_at in T-24h, T-1h, T=0 ±30s windows
    PERFORM cron.schedule(
      'send-followup-notifications',
      '* * * * *',
      $cron$
        SELECT net.http_post(
          url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1)
                     || '/functions/v1/send-followup-notifications',
          headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
          ),
          body    := '{}'::jsonb
        );
      $cron$
    );

    -- Mark overdue follow-ups and send overdue push notifications every 5 minutes
    PERFORM cron.schedule(
      'process-overdue-followups',
      '*/5 * * * *',
      $cron$
        SELECT public.mark_overdue_followups();
        SELECT net.http_post(
          url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1)
                     || '/functions/v1/process-overdue-followups',
          headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
          ),
          body    := '{}'::jsonb
        );
      $cron$
    );

  END IF;
END;
$$;
