-- Story 8.3 — Harden verify_jwt=false cron Edge Functions.
--
-- The 3 pg_cron-invoked edge fns (send-followup-notifications, process-overdue-followups,
-- streak-at-risk) now require a shared secret in the `x-cron-secret` header (enforced
-- in-function by requireCronSecret()). This migration re-schedules the 3 jobs to send it.
--
-- The secret is NOT hardcoded here — it is read at each cron tick from a vault secret
-- named 'cron_secret'. It must match the CRON_SECRET set on the edge functions.
--
-- POST-DEPLOY (one-time, both values IDENTICAL — see deploy notes in the story):
--   1. Vault (for the cron SQL below):
--        SELECT vault.create_secret('<SECRET>', 'cron_secret');
--   2. Edge functions (for requireCronSecret):
--        supabase secrets set CRON_SECRET='<SECRET>'
--   Generate once, e.g. `openssl rand -hex 32`. Rotating = update BOTH.
--
-- Note: cron.schedule() upserts by job name — re-scheduling an existing job name
-- replaces its definition in place, so the previous 0026/0032 schedules are superseded.
-- Roll-forward only. Never edit after apply.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN

    -- send-followup-notifications — every minute (was 0026, Bearer only → +x-cron-secret)
    PERFORM cron.schedule(
      'send-followup-notifications',
      '* * * * *',
      $cron$
        SELECT net.http_post(
          url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1)
                     || '/functions/v1/send-followup-notifications',
          headers := jsonb_build_object(
            'Content-Type',   'application/json',
            'Authorization',  'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1),
            'x-cron-secret',  (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret' LIMIT 1)
          ),
          body    := '{}'::jsonb
        );
      $cron$
    );

    -- process-overdue-followups — every 5 min; still runs mark_overdue_followups() first
    PERFORM cron.schedule(
      'process-overdue-followups',
      '*/5 * * * *',
      $cron$
        SELECT public.mark_overdue_followups();
        SELECT net.http_post(
          url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1)
                     || '/functions/v1/process-overdue-followups',
          headers := jsonb_build_object(
            'Content-Type',   'application/json',
            'Authorization',  'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1),
            'x-cron-secret',  (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret' LIMIT 1)
          ),
          body    := '{}'::jsonb
        );
      $cron$
    );

    -- streak-at-risk — every 30 min (was 0032, NO auth header at all → +x-cron-secret)
    PERFORM cron.schedule(
      'streak-at-risk',
      '0,30 * * * *',
      $cron$
        SELECT net.http_post(
          url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1)
                     || '/functions/v1/streak-at-risk',
          headers := jsonb_build_object(
            'Content-Type',   'application/json',
            'x-cron-secret',  (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret' LIMIT 1)
          ),
          body    := '{}'::jsonb
        );
      $cron$
    );

  END IF;
END;
$$;
