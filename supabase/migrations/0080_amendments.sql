-- 0080_amendments.sql
-- Story 16.1 (Epic 16) — FR-56/FR-57. Amendment schema with an immutable event trail.
--
-- Three tables (mirrors the immutable lead_timeline pattern 0012/0015):
--   amendments            — modification requests against a unit/lead (mutable status).
--   amendment_events      — APPEND-ONLY trail. Authenticated may SELECT only; inserts go through the
--                           SECURITY DEFINER helper log_amendment_event() (no UPDATE/DELETE ever).
--   tenant_execution_team — membership (NOT a role tier); head-managed DML (mirrors agencies/0057).
--
-- File-based migration; never MCP apply.

BEGIN;

-- enum --------------------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'amendment_status') THEN
    CREATE TYPE public.amendment_status AS ENUM ('requested', 'acknowledged', 'in_progress', 'done', 'rejected');
  END IF;
END $$;

-- 1. amendments -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.amendments (
  id          uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  unit_id     uuid NOT NULL REFERENCES public.units(id)   ON DELETE RESTRICT,
  lead_id     uuid NOT NULL REFERENCES public.leads(id)   ON DELETE RESTRICT,
  description text NOT NULL,
  status      public.amendment_status NOT NULL DEFAULT 'requested',
  logged_by   uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS amendments_tenant_status_idx ON public.amendments (tenant_id, status);
CREATE INDEX IF NOT EXISTS amendments_unit_idx          ON public.amendments (unit_id);
CREATE INDEX IF NOT EXISTS amendments_lead_idx          ON public.amendments (lead_id);

ALTER TABLE public.amendments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amendments FORCE  ROW LEVEL SECURITY;

DROP POLICY IF EXISTS amendments_tenant_isolation ON public.amendments;
CREATE POLICY amendments_tenant_isolation ON public.amendments
  FOR ALL TO authenticated
  USING      (tenant_id = public.auth_tenant_id())
  WITH CHECK (tenant_id = public.auth_tenant_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.amendments TO authenticated;

CREATE TRIGGER amendments_set_updated_at
  BEFORE UPDATE ON public.amendments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 2. amendment_events (append-only) ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.amendment_events (
  id            uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  amendment_id  uuid NOT NULL REFERENCES public.amendments(id) ON DELETE CASCADE,
  actor_user_id uuid,
  actor_role    text,
  event_type    text NOT NULL,                         -- 'logged' | 'status_changed' | 'note_added'
  from_status   public.amendment_status,
  to_status     public.amendment_status,
  note          text,
  occurred_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS amendment_events_amendment_idx ON public.amendment_events (amendment_id, occurred_at);

ALTER TABLE public.amendment_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amendment_events FORCE  ROW LEVEL SECURITY;

-- SELECT only for app roles; INSERT only via the definer helper; never UPDATE/DELETE.
DROP POLICY IF EXISTS amendment_events_select ON public.amendment_events;
CREATE POLICY amendment_events_select ON public.amendment_events
  FOR SELECT TO authenticated
  USING (tenant_id = public.auth_tenant_id());

GRANT SELECT ON public.amendment_events TO authenticated;
-- Supabase default privileges grant ALL on new public tables to authenticated/anon; explicitly
-- REVOKE every mutation so amendment_events is truly append-only (hard error, not a silent RLS 0-row).
-- The only INSERT path is the SECURITY DEFINER helper log_amendment_event() (runs as owner).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.amendment_events FROM authenticated, anon, PUBLIC;

-- append-only writer (SECURITY DEFINER; bypasses the SELECT-only grant)
CREATE OR REPLACE FUNCTION public.log_amendment_event(
  p_amendment_id uuid,
  p_event_type   text,
  p_from_status  public.amendment_status DEFAULT NULL,
  p_to_status    public.amendment_status DEFAULT NULL,
  p_note         text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_event_id  uuid;
BEGIN
  SELECT tenant_id INTO v_tenant_id FROM public.amendments WHERE id = p_amendment_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'amendment_not_found' USING ERRCODE = 'P0001';
  END IF;
  -- if called with a JWT, enforce same-tenant; system callers (no JWT) skip this
  IF public.auth_tenant_id() IS NOT NULL AND public.auth_tenant_id() <> v_tenant_id THEN
    RAISE EXCEPTION 'cross_tenant_forbidden' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.amendment_events (tenant_id, amendment_id, actor_user_id, actor_role, event_type, from_status, to_status, note, occurred_at)
  VALUES (v_tenant_id, p_amendment_id, auth.uid(), (auth.jwt() -> 'app_metadata') ->> 'role',
          p_event_type, p_from_status, p_to_status, p_note, now())
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$$;

REVOKE ALL ON FUNCTION public.log_amendment_event(uuid, text, public.amendment_status, public.amendment_status, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.log_amendment_event(uuid, text, public.amendment_status, public.amendment_status, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.log_amendment_event(uuid, text, public.amendment_status, public.amendment_status, text) IS
  'Story 16.1 — append-only writer for amendment_events (the only INSERT path). Same-tenant enforced when a JWT is present.';

-- 3. tenant_execution_team (membership; head-managed) ---------------------------------------
CREATE TABLE IF NOT EXISTS public.tenant_execution_team (
  tenant_id  uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.users(id)   ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, user_id)
);

ALTER TABLE public.tenant_execution_team ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_execution_team FORCE  ROW LEVEL SECURITY;

DROP POLICY IF EXISTS execution_team_select       ON public.tenant_execution_team;
DROP POLICY IF EXISTS execution_team_admin_insert ON public.tenant_execution_team;
DROP POLICY IF EXISTS execution_team_admin_delete ON public.tenant_execution_team;

CREATE POLICY execution_team_select ON public.tenant_execution_team
  FOR SELECT TO authenticated
  USING (tenant_id = public.auth_tenant_id());

CREATE POLICY execution_team_admin_insert ON public.tenant_execution_team
  FOR INSERT TO authenticated
  WITH CHECK (tenant_id = public.auth_tenant_id() AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin');

CREATE POLICY execution_team_admin_delete ON public.tenant_execution_team
  FOR DELETE TO authenticated
  USING (tenant_id = public.auth_tenant_id() AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin');

GRANT SELECT, INSERT, DELETE ON public.tenant_execution_team TO authenticated;

COMMENT ON TABLE public.tenant_execution_team IS
  'Story 16.1 — execution-team membership (NOT a role tier). Head-managed (admin-only DML). Members manage amendment status (16.3).';

COMMIT;
