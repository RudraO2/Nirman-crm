-- Story 1.3 — User account lifecycle event log
-- Satisfies AC-5 (account_created), extended by Stories 1.5 (password_changed) and 1.6 (deactivated/reactivated)
-- Append-only: no UPDATE/DELETE grants.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_event_type') THEN
    CREATE TYPE public.user_event_type AS ENUM (
      'account_created',
      'account_deactivated',
      'account_reactivated',
      'password_changed',
      'password_reset_by_admin'
    );
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.user_events (
  id           uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  user_id      uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  actor_id     uuid REFERENCES public.users(id) ON DELETE SET NULL,
  event_type   public.user_event_type NOT NULL,
  payload      jsonb NOT NULL DEFAULT '{}',
  occurred_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.user_events IS
  'Story 1.3 — Append-only user account lifecycle events. Never UPDATE or DELETE rows.';

CREATE INDEX IF NOT EXISTS user_events_tenant_id_idx   ON public.user_events (tenant_id);
CREATE INDEX IF NOT EXISTS user_events_user_id_idx     ON public.user_events (user_id);
CREATE INDEX IF NOT EXISTS user_events_occurred_at_idx ON public.user_events (occurred_at DESC);

ALTER TABLE public.user_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_events FORCE  ROW LEVEL SECURITY;

CREATE POLICY user_events_tenant_isolation ON public.user_events
  FOR ALL
  TO authenticated
  USING      (tenant_id = ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid)
  WITH CHECK (tenant_id = ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid);

-- READ + INSERT for authenticated; NO UPDATE, NO DELETE — append-only
GRANT SELECT, INSERT ON public.user_events TO authenticated;
