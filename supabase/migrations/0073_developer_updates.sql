-- 0073_developer_updates.sql
-- Story 14.4 (Epic 14) — FR-50. Developer-updates broadcast channel.
--
-- NOTE: the story referenced a "pending_notifications" table/dispatcher; the real codebase has no
-- such table — notifications are sent by per-event edge functions (e.g. send-assignment-notification)
-- that fan out FCM to device_tokens. This story follows that real pattern: post_developer_update
-- inserts the row + emits a domain_event; a new edge fn `send-developer-update` resolves recipients
-- via get_developer_update_audience() and pushes FCM. (Edge deploy deferred with the batch.)
--
-- Partner opt-in: shareable_to_partners default FALSE. Partners see/receive an update only if it is
-- shareable AND its project is shared to their agency (agency_projects, 0072). Enforced both in the
-- developer_updates SELECT RLS policy (privacy at rest) and in the audience resolver (who gets pushed).
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

-- 1. enum -----------------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'dev_update_type') THEN
    CREATE TYPE public.dev_update_type AS ENUM ('construction', 'pricing', 'inventory', 'announcement');
  END IF;
END $$;

-- 2. table ----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.developer_updates (
  id                    uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id             uuid NOT NULL REFERENCES public.tenants(id)  ON DELETE CASCADE,
  project_id            uuid REFERENCES public.projects(id) ON DELETE CASCADE,   -- NULL = tenant-wide announcement
  update_type           public.dev_update_type NOT NULL,
  body                  text NOT NULL,
  shareable_to_partners boolean NOT NULL DEFAULT false,
  posted_by             uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS developer_updates_tenant_created_idx ON public.developer_updates (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS developer_updates_project_idx        ON public.developer_updates (project_id);

ALTER TABLE public.developer_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_updates FORCE  ROW LEVEL SECURITY;

-- SELECT: tenant members; partners only see shareable updates for projects shared to their agency.
DROP POLICY IF EXISTS developer_updates_select ON public.developer_updates;
CREATE POLICY developer_updates_select ON public.developer_updates
  FOR SELECT TO authenticated
  USING (
    tenant_id = public.auth_tenant_id()
    AND (
      public.auth_role_tier() IS DISTINCT FROM 'partner_agency'
      OR (
        shareable_to_partners = true
        AND project_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.agency_projects ap
          JOIN public.users u ON u.agency_id = ap.agency_id
          WHERE u.id = auth.uid()
            AND ap.tenant_id = developer_updates.tenant_id
            AND ap.project_id = developer_updates.project_id
        )
      )
    )
  );

-- No direct INSERT/UPDATE/DELETE grant: writes go through post_developer_update (SECURITY DEFINER).
GRANT SELECT ON public.developer_updates TO authenticated;

COMMENT ON TABLE public.developer_updates IS
  'Story 14.4 — builder broadcast feed. Partners see only shareable updates for agency-shared projects (RLS). One-way (no replies) in V2.';

-- 3. post_developer_update — head-only insert + domain_event --------------------------------
CREATE OR REPLACE FUNCTION public.post_developer_update(
  p_update_type           public.dev_update_type,
  p_body                  text,
  p_project_id            uuid    DEFAULT NULL,
  p_shareable_to_partners boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_id        uuid;
BEGIN
  IF public.auth_role_tier() IS DISTINCT FROM 'builder_head' THEN
    RAISE EXCEPTION 'permission_denied: builder_head only' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  IF p_body IS NULL OR length(trim(p_body)) = 0 THEN
    RAISE EXCEPTION 'body_required' USING ERRCODE = 'P0001';
  END IF;
  IF p_project_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.projects WHERE id = p_project_id AND tenant_id = v_tenant_id) THEN
    RAISE EXCEPTION 'project_not_found' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.developer_updates (tenant_id, project_id, update_type, body, shareable_to_partners, posted_by)
  VALUES (v_tenant_id, p_project_id, p_update_type, p_body, COALESCE(p_shareable_to_partners, false), auth.uid())
  RETURNING id INTO v_id;

  -- event for the FCM fan-out producer (send-developer-update edge fn)
  INSERT INTO public.domain_events (tenant_id, event_type, payload, occurred_at)
  VALUES (v_tenant_id, 'developer_update_posted',
          jsonb_build_object('update_id', v_id, 'project_id', p_project_id, 'shareable_to_partners', COALESCE(p_shareable_to_partners, false)),
          now());

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.post_developer_update(public.dev_update_type, text, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.post_developer_update(public.dev_update_type, text, uuid, boolean) TO authenticated;

COMMENT ON FUNCTION public.post_developer_update(public.dev_update_type, text, uuid, boolean) IS
  'Story 14.4 — builder_head posts a developer update (+domain_event for FCM fan-out). Returns the new update id.';

-- 4. get_developer_updates — in-app feed (RLS does tier filtering; SECURITY INVOKER) ---------
CREATE OR REPLACE FUNCTION public.get_developer_updates(
  p_project_id uuid DEFAULT NULL,
  p_limit      int  DEFAULT 50,
  p_offset     int  DEFAULT 0
)
RETURNS TABLE (
  id            uuid,
  project_id    uuid,
  update_type   public.dev_update_type,
  body          text,
  shareable_to_partners boolean,
  posted_by     uuid,
  posted_by_name text,
  created_at    timestamptz
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, extensions
AS $$
  SELECT d.id, d.project_id, d.update_type, d.body, d.shareable_to_partners,
         d.posted_by, u.email_or_username, d.created_at
  FROM public.developer_updates d
  LEFT JOIN public.users u ON u.id = d.posted_by
  WHERE (p_project_id IS NULL OR d.project_id = p_project_id)
  ORDER BY d.created_at DESC
  LIMIT p_limit OFFSET p_offset;
$$;

REVOKE ALL ON FUNCTION public.get_developer_updates(uuid, int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_developer_updates(uuid, int, int) TO authenticated;

COMMENT ON FUNCTION public.get_developer_updates(uuid, int, int) IS
  'Story 14.4 — in-app updates feed, newest-first, attributed. SECURITY INVOKER: developer_updates RLS scopes partners to shareable+agency-shared rows automatically.';

-- 5. get_developer_update_audience — recipient user_ids for FCM fan-out (edge fn) ------------
CREATE OR REPLACE FUNCTION public.get_developer_update_audience(p_update_id uuid)
RETURNS TABLE (user_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_upd public.developer_updates;
BEGIN
  SELECT * INTO v_upd FROM public.developer_updates WHERE id = p_update_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  RETURN QUERY
  -- internal sales team (everyone non-external in the tenant)
  SELECT u.id
  FROM public.users u
  WHERE u.tenant_id = v_upd.tenant_id
    AND u.is_active = true
    AND COALESCE(u.is_external, false) = false
  UNION
  -- partner agency users — only if the update is shareable AND their agency is shared to the project
  SELECT u.id
  FROM public.users u
  JOIN public.agency_projects ap
    ON ap.agency_id = u.agency_id
   AND ap.tenant_id = v_upd.tenant_id
   AND ap.project_id = v_upd.project_id
  WHERE u.tenant_id = v_upd.tenant_id
    AND u.is_active = true
    AND u.role_tier = 'partner_agency'
    AND v_upd.shareable_to_partners = true
    AND v_upd.project_id IS NOT NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.get_developer_update_audience(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_developer_update_audience(uuid) TO service_role;

COMMENT ON FUNCTION public.get_developer_update_audience(uuid) IS
  'Story 14.4 — resolves recipient user_ids for an update: internal team always; partner_agency users only if shareable + agency-shared project. Consumed by send-developer-update edge fn (service_role).';

COMMIT;
