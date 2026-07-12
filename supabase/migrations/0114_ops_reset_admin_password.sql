-- 0114_ops_reset_admin_password.sql
-- Second-admin path, part B (practicality backlog P1): founder resets a builder
-- ADMIN's forgotten password from the ops console — previously founder-level
-- SQL surgery (nirman-crm/CLAUDE.md §Password reset documents the manual dual-
-- store recipe; this productizes exactly that recipe).
--
-- ops_reset_tenant_admin_password(p_tenant_id, p_username default null):
--   * platform-admin only (is_platform_admin — aal2-enforced since 0100).
--   * p_username null → the tenant's single admin; multiple admins → error
--     listing usernames so the founder picks one explicitly.
--   * One temp password, BOTH stores in lockstep ($2a bcrypt via extensions
--     pgcrypto — GoTrue + bcryptjs + login fn all accept it), like
--     create-employee / reset-employee-password.
--   * must_change_password=true; all sessions + refresh tokens revoked.
--   * ops_audit_log row (NEVER the password). Temp password returned ONCE.
-- File-based migration; never MCP apply.

BEGIN;

CREATE OR REPLACE FUNCTION public.ops_reset_tenant_admin_password(
  p_tenant_id uuid,
  p_username  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user   RECORD;
  v_count  int;
  v_names  text;
  v_temp   text;
  v_hash   text;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_username IS NULL THEN
    SELECT count(*) INTO v_count
    FROM public.users u
    WHERE u.tenant_id = p_tenant_id AND u.role = 'admin' AND u.is_active;
    IF v_count = 0 THEN
      RAISE EXCEPTION 'no_active_admin_for_tenant' USING ERRCODE = 'P0002';
    ELSIF v_count > 1 THEN
      SELECT string_agg(u.email_or_username, ', ' ORDER BY u.created_at) INTO v_names
      FROM public.users u
      WHERE u.tenant_id = p_tenant_id AND u.role = 'admin' AND u.is_active;
      RAISE EXCEPTION 'multiple_admins_specify_username: %', v_names USING ERRCODE = 'P0001';
    END IF;
    SELECT u.id, u.email_or_username INTO v_user
    FROM public.users u
    WHERE u.tenant_id = p_tenant_id AND u.role = 'admin' AND u.is_active;
  ELSE
    SELECT u.id, u.email_or_username INTO v_user
    FROM public.users u
    WHERE u.tenant_id = p_tenant_id AND u.role = 'admin' AND u.is_active
      AND lower(u.email_or_username) = lower(btrim(p_username));
    IF NOT FOUND THEN
      RAISE EXCEPTION 'admin_not_found_for_username' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  -- Readable one-time password; forced change on first login anyway.
  v_temp := 'Nirman-' || encode(extensions.gen_random_bytes(6), 'hex');
  v_hash := extensions.crypt(v_temp, extensions.gen_salt('bf', 12));

  -- BOTH stores in lockstep (login verifies public.users first, then GoTrue).
  UPDATE auth.users
     SET encrypted_password = v_hash, updated_at = now()
   WHERE id = v_user.id;

  UPDATE public.users
     SET bcrypt_password_hash = v_hash,
         must_change_password = true
   WHERE id = v_user.id;

  -- Revoke every live session so a stolen/old session dies with the reset.
  DELETE FROM auth.sessions       WHERE user_id = v_user.id;
  DELETE FROM auth.refresh_tokens WHERE user_id = v_user.id::text;

  INSERT INTO public.ops_audit_log (actor_user_id, action, target_tenant_id, detail)
  VALUES (auth.uid(), 'reset_admin_password', p_tenant_id,
          jsonb_build_object('admin_user_id', v_user.id, 'username', v_user.email_or_username));

  RETURN jsonb_build_object(
    'username',      v_user.email_or_username,
    'temp_password', v_temp
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ops_reset_tenant_admin_password(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_reset_tenant_admin_password(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.ops_reset_tenant_admin_password(uuid, text) IS
  '0114 — platform-admin resets a builder admin''s password: one $2a hash to BOTH stores, must_change_password=true, all sessions revoked, audit-logged (password never persisted). Returns {username, temp_password} ONCE. p_username required when the tenant has multiple admins.';

COMMIT;
