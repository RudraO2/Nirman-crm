-- Story 2.2 (code review patches) — P-1, P-2, P-3, P-4, D-1
-- P-1: p_lead_id cross-tenant ownership check in log_timeline_event()
-- P-2: auth_tenant_id() NULL guard in log_timeline_event()
-- P-3: domain_events.tenant_id FK to tenants (missing; lead_timeline had it)
-- P-4: Extract single now() variable in log_timeline_event() (identical timestamps)
-- D-1: Revoke direct INSERT on lead_timeline from authenticated; drop INSERT policy
--       All writes must go through log_timeline_event() SECURITY DEFINER
--
-- Roll-forward only. Never edit after apply.

-- ────────────────────────────────────────────────────────────────────────────
-- D-1: Remove direct INSERT path for authenticated role on lead_timeline
-- All inserts must go through log_timeline_event() SECURITY DEFINER.
-- The SECURITY DEFINER function owner (postgres, BYPASSRLS) can still insert.
-- ────────────────────────────────────────────────────────────────────────────
REVOKE INSERT ON public.lead_timeline FROM authenticated;

DROP POLICY IF EXISTS lead_timeline_insert ON public.lead_timeline;

-- ────────────────────────────────────────────────────────────────────────────
-- P-3: Add tenant_id FK to domain_events
-- lead_timeline had REFERENCES public.tenants(id) ON DELETE RESTRICT.
-- domain_events was missing this constraint — orphaned events possible.
-- Using CASCADE (not RESTRICT) because domain_events are owned data, not owners.
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.domain_events
  ADD CONSTRAINT domain_events_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;

COMMENT ON CONSTRAINT domain_events_tenant_id_fkey ON public.domain_events IS
  'Story 2.2 review P-3 — Tenant FK added post-review; domain_events deleted when tenant deleted.';

-- ────────────────────────────────────────────────────────────────────────────
-- P-1 + P-2 + P-4: Patched log_timeline_event()
--   P-2: NULL guard for v_tenant_id (clean exception vs constraint error)
--   P-1: p_lead_id ownership check (prevents cross-tenant lead reference)
--   P-4: Single v_occurred_at variable (both rows guaranteed identical timestamp)
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
  v_occurred_at   timestamptz;
BEGIN
  v_tenant_id     := public.auth_tenant_id();
  v_actor_user_id := auth.uid();
  v_actor_role    := (auth.jwt() -> 'app_metadata') ->> 'role';

  -- P-2: guard against missing tenant context (clean error instead of NOT NULL violation)
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'missing_tenant_context: app_metadata.tenant_id not set in JWT'
      USING ERRCODE = 'P0001';
  END IF;

  -- P-1: verify p_lead_id belongs to caller's tenant (prevent cross-tenant reference)
  IF NOT EXISTS (
    SELECT 1 FROM public.leads
    WHERE id = p_lead_id AND tenant_id = v_tenant_id
  ) THEN
    RAISE EXCEPTION 'lead_not_found: lead % not found in tenant %', p_lead_id, v_tenant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- P-4: capture single timestamp — both rows guaranteed identical for correlation queries
  v_occurred_at := now();

  INSERT INTO public.lead_timeline (
    tenant_id, lead_id, actor_user_id, actor_role, event_type, payload, occurred_at
  ) VALUES (
    v_tenant_id, p_lead_id, v_actor_user_id, v_actor_role, p_event_type, p_payload, v_occurred_at
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
    v_occurred_at
  );

  RETURN v_timeline_id;
END;
$$;

COMMENT ON FUNCTION public.log_timeline_event(uuid, public.timeline_event_type, jsonb) IS
  'Story 2.2 (patched) — Sole write path for lead_timeline + domain_events. SECURITY DEFINER. Validates tenant context (P-2) and lead ownership (P-1). Atomic dual-write (Architecture Decision 14).';
