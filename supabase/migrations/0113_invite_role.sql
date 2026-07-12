-- 0113_invite_role.sql
-- Second-admin path, part A (practicality backlog P1): invites can now create
-- ADMINS, not just employees. Removes the founder from "builder wants a second
-- admin" — the existing admin self-serves via the same invite-link flow.
--
-- invitations.invited_role ('employee' default | 'admin'), minted only by an
-- existing admin of the tenant (create_invitation is already admin-guarded —
-- an admin can only grant what they already hold, no escalation). accept-invite
-- reads the role off the claimed row for both stores.
--
-- create_invitation gains a p_role param — signature change, so the old
-- (text) overload is DROPPED (two overloads would make PostgREST rpc calls
-- ambiguous). File-based migration; never MCP apply.

BEGIN;

ALTER TABLE public.invitations
  ADD COLUMN IF NOT EXISTS invited_role text NOT NULL DEFAULT 'employee'
  CHECK (invited_role IN ('employee', 'admin'));

DROP FUNCTION IF EXISTS public.create_invitation(text);

CREATE FUNCTION public.create_invitation(p_label text, p_role text DEFAULT 'employee')
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
  IF p_role NOT IN ('employee', 'admin') THEN
    RAISE EXCEPTION 'invalid_role: employee or admin' USING ERRCODE = 'P0001';
  END IF;

  -- 32 random bytes, url-safe hex — the raw token exists only in this response.
  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.invitations (tenant_id, label, invited_role, token_hash, created_by, expires_at)
  VALUES (v_tenant_id, btrim(p_label), p_role,
          encode(extensions.digest(v_token, 'sha256'), 'hex'),
          auth.uid(), v_expires)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id, 'token', v_token, 'expires_at', v_expires, 'role', p_role);
END;
$$;

REVOKE ALL ON FUNCTION public.create_invitation(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_invitation(text, text) TO authenticated;

COMMENT ON FUNCTION public.create_invitation(text, text) IS
  'Story 8.4 + 0113 — admin mints a single-use 7-day invite link for an employee OR a second admin (no escalation: minting requires the admin role being granted). Raw token returned ONCE; only sha256 stored.';

COMMIT;
