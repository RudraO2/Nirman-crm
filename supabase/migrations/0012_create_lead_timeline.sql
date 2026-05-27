-- Story 2.2 — Lead Timeline schema and write helper
-- FRs: FR-19 (immutable audit trail, 21 event types)
-- Architecture Decision 14: domain_events written in same TX as lead_timeline (no dual-write risk)
-- NFR-8 (immutable audit), NFR-11 (RLS), NFR-12 (append-only)
--
-- Roll-forward only. Never edit after apply.

-- ────────────────────────────────────────────────────────────────────────────
-- 1. timeline_event_type enum (21 values from FR-19)
-- ────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'timeline_event_type' AND n.nspname = 'public'
  ) THEN
    CREATE TYPE public.timeline_event_type AS ENUM (
      'lead_created',
      'field_updated',
      'status_changed',
      'call_initiated',
      'call_outcome_cleared',
      'whatsapp_sent',
      'followup_set',
      'followup_rescheduled',
      'followup_overdue',
      'followup_completed',
      'visit_date_set',
      'visit_rescheduled',
      'assigned',
      'reassigned',
      'shared',
      'share_revoked',
      'archived',
      'restored',
      'duplicate_override',
      'remark_added',
      'imported'
    );
  END IF;
END
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. lead_timeline — immutable append-only audit log
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.lead_timeline (
  id            uuid        PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id     uuid        NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  lead_id       uuid        NOT NULL REFERENCES public.leads(id) ON DELETE CASCADE,
  actor_user_id uuid                 REFERENCES public.users(id) ON DELETE SET NULL,
  actor_role    text,
  event_type    public.timeline_event_type NOT NULL,
  payload       jsonb       NOT NULL DEFAULT '{}',
  occurred_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.lead_timeline IS
  'Story 2.2 — Immutable audit log for all lead lifecycle events. Append-only; no UPDATE/DELETE permitted.';
COMMENT ON COLUMN public.lead_timeline.actor_user_id IS
  'NULL for system-generated events (cron, automation).';
COMMENT ON COLUMN public.lead_timeline.actor_role IS
  'text (not user_role enum) to allow ''system'' actor for cron/automation events.';

-- ────────────────────────────────────────────────────────────────────────────
-- 3. lead_timeline RLS — append-only, tenant-scoped
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.lead_timeline ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_timeline FORCE ROW LEVEL SECURITY;

-- SELECT: own tenant rows only
CREATE POLICY lead_timeline_select
  ON public.lead_timeline
  FOR SELECT
  TO authenticated
  USING (tenant_id = public.auth_tenant_id());

-- INSERT: own tenant rows only
-- No UPDATE or DELETE policy — FORCE RLS default-denies them
CREATE POLICY lead_timeline_insert
  ON public.lead_timeline
  FOR INSERT
  TO authenticated
  WITH CHECK (tenant_id = public.auth_tenant_id());

-- Grants: SELECT + INSERT only — UPDATE/DELETE deliberately omitted
GRANT SELECT, INSERT ON public.lead_timeline TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. lead_timeline indexes
-- ────────────────────────────────────────────────────────────────────────────
-- Primary query: timeline for a lead, newest first
CREATE INDEX IF NOT EXISTS lead_timeline_lead_id_occurred_at_idx
  ON public.lead_timeline (lead_id, occurred_at DESC);

-- FK + RLS support
CREATE INDEX IF NOT EXISTS lead_timeline_tenant_id_idx
  ON public.lead_timeline (tenant_id);

-- FK index (partial — skip NULLs for system events)
CREATE INDEX IF NOT EXISTS lead_timeline_actor_user_id_idx
  ON public.lead_timeline (actor_user_id)
  WHERE actor_user_id IS NOT NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- 5. domain_events — generic event bus (AI V3 seam, Decision 14)
-- No FK to leads — generic; lead_id stored in payload for lead-scoped events
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.domain_events (
  id          uuid        PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id   uuid        NOT NULL,
  event_type  text        NOT NULL,
  payload     jsonb       NOT NULL DEFAULT '{}',
  occurred_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.domain_events IS
  'Story 2.2 — Generic event bus written atomically with lead_timeline. AI V3 seam (Architecture Decision 14). No FK to leads; future events may be non-lead-scoped.';

-- ────────────────────────────────────────────────────────────────────────────
-- 6. domain_events RLS — tenant-scoped SELECT only
-- INSERT is via log_timeline_event() SECURITY DEFINER only — no direct INSERT for authenticated
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.domain_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.domain_events FORCE ROW LEVEL SECURITY;

-- SELECT: own tenant rows only
CREATE POLICY domain_events_select
  ON public.domain_events
  FOR SELECT
  TO authenticated
  USING (tenant_id = public.auth_tenant_id());

-- No INSERT policy for authenticated — writes only via SECURITY DEFINER function
GRANT SELECT ON public.domain_events TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 7. domain_events index
-- ────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS domain_events_tenant_id_occurred_at_idx
  ON public.domain_events (tenant_id, occurred_at DESC);

-- ────────────────────────────────────────────────────────────────────────────
-- 8. log_timeline_event() — atomic write helper (SECURITY DEFINER)
-- Writes lead_timeline + domain_events in same transaction.
-- SECURITY DEFINER needed so authenticated callers can write domain_events
-- (which has no INSERT policy for authenticated role).
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.log_timeline_event(
  p_lead_id    uuid,
  p_event_type public.timeline_event_type,
  p_payload    jsonb DEFAULT '{}'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_tenant_id     uuid;
  v_actor_user_id uuid;
  v_actor_role    text;
  v_timeline_id   uuid;
BEGIN
  v_tenant_id     := public.auth_tenant_id();
  v_actor_user_id := auth.uid();
  v_actor_role    := (auth.jwt() -> 'app_metadata') ->> 'role';

  INSERT INTO public.lead_timeline (
    tenant_id, lead_id, actor_user_id, actor_role, event_type, payload, occurred_at
  ) VALUES (
    v_tenant_id, p_lead_id, v_actor_user_id, v_actor_role, p_event_type, p_payload, now()
  )
  RETURNING id INTO v_timeline_id;

  -- Architecture Decision 14: domain_events in same TX — no dual-write risk
  INSERT INTO public.domain_events (
    tenant_id, event_type, payload, occurred_at
  ) VALUES (
    v_tenant_id,
    p_event_type::text,
    jsonb_build_object(
      'lead_id',       p_lead_id,
      'actor_user_id', v_actor_user_id,
      'actor_role',    v_actor_role,
      'timeline_id',   v_timeline_id,
      'event_payload', p_payload
    ),
    now()
  );

  RETURN v_timeline_id;
END;
$$;

COMMENT ON FUNCTION public.log_timeline_event(uuid, public.timeline_event_type, jsonb) IS
  'Story 2.2 — Atomic write to lead_timeline + domain_events. SECURITY DEFINER to write domain_events on behalf of authenticated callers. Returns new lead_timeline.id.';

GRANT EXECUTE ON FUNCTION public.log_timeline_event(uuid, public.timeline_event_type, jsonb)
  TO authenticated;
