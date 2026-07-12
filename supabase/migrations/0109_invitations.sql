-- 0109_invitations.sql
-- Story 8.4 — team invites (LINK-based; no SMTP dependency, fits the WhatsApp-
-- first founder-led motion — email delivery is Story 8.5, later).
--
-- Flow: admin calls create_invitation(label) → gets the RAW token exactly once →
-- shares https://<admin-app>/invite/<token> over WhatsApp → invitee opens the
-- public accept page → accept-invite edge fn (service-role, token IS the
-- credential per the 8.3 standing rule) creates the employee account and burns
-- the invitation.
--
-- Security shape (post-0098/0099 house style):
--   * Only sha256(token) is stored — a DB read never yields a usable link.
--   * Writes are RPC-only (create_invitation / revoke_invitation, admin-guarded).
--     Direct grants: SELECT only, admin-scoped by RLS, for the Team-page list.
--   * Single-use enforced atomically by the edge fn's claim UPDATE
--     (accepted_at IS NULL) — no TOCTOU between two accepts of the same token.
--   * V1 invites create role='employee' only (admins are provisioned by ops).
-- File-based migration; never MCP apply.

BEGIN;

CREATE TABLE IF NOT EXISTS public.invitations (
  id               uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id        uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  label            text NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 80),
  token_hash       text NOT NULL UNIQUE,
  created_by       uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at       timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz NOT NULL,
  revoked_at       timestamptz,
  accepted_at      timestamptz,
  accepted_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS invitations_tenant_idx ON public.invitations (tenant_id, created_at DESC);

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitations FORCE  ROW LEVEL SECURITY;

-- Admin of the tenant may list; nobody writes directly (RPC/edge-fn only).
DROP POLICY IF EXISTS invitations_admin_select ON public.invitations;
CREATE POLICY invitations_admin_select ON public.invitations
  FOR SELECT TO authenticated
  USING (tenant_id = public.auth_tenant_id()
         AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin');

GRANT SELECT ON public.invitations TO authenticated;

COMMENT ON TABLE public.invitations IS
  'Story 8.4 — link-based team invites. Stores sha256(token) only; raw token shown once by create_invitation. Single-use (accepted_at claim), 7-day expiry, revocable. Writes RPC-only.';

-- ── create_invitation ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_invitation(p_label text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_token     text;
  v_id        uuid;
  v_expires   timestamptz := now() + interval '7 days';
BEGIN
  IF (auth.jwt() -> 'app_metadata') ->> 'role' IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied: admin only' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'missing_tenant_context' USING ERRCODE = 'P0001';
  END IF;
  IF length(btrim(coalesce(p_label, ''))) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'invalid_label: 1-80 characters' USING ERRCODE = 'P0001';
  END IF;

  -- 32 random bytes, url-safe hex — the raw token exists only in this response.
  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.invitations (tenant_id, label, token_hash, created_by, expires_at)
  VALUES (v_tenant_id, btrim(p_label),
          encode(extensions.digest(v_token, 'sha256'), 'hex'),
          auth.uid(), v_expires)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id, 'token', v_token, 'expires_at', v_expires);
END;
$$;

REVOKE ALL ON FUNCTION public.create_invitation(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_invitation(text) TO authenticated;

COMMENT ON FUNCTION public.create_invitation(text) IS
  'Story 8.4 — admin mints a single-use 7-day invite link. Returns the raw token ONCE; only its sha256 is stored.';

-- ── revoke_invitation ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_invitation(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  IF (auth.jwt() -> 'app_metadata') ->> 'role' IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied: admin only' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  UPDATE public.invitations
     SET revoked_at = now()
   WHERE id = p_id AND tenant_id = v_tenant_id
     AND accepted_at IS NULL AND revoked_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation_not_revocable: unknown, already accepted, or already revoked'
      USING ERRCODE = 'P0001';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_invitation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_invitation(uuid) TO authenticated;

COMMENT ON FUNCTION public.revoke_invitation(uuid) IS
  'Story 8.4 — admin revokes a pending (unaccepted, unrevoked) invite of their own tenant.';

COMMIT;
