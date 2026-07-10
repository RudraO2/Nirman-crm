-- 0091_provision_tenant.sql
-- Story 9.5 (Epic 9) — ops console: provision a NEW builder (tenant + first admin).
--
-- The "add a new builder" seam the ops console's /provision screen drives. Closes
-- the gap left by 9.4 (which only operated on EXISTING tenants). Same architecture
-- as the rest of the ops backend (9.2): RLS-native, platform-admin-guarded
-- SECURITY DEFINER RPC, audit-logged, NO service-role key in any client.
--
-- WHY a SQL fn and not the create-employee/bootstrap-admin edge-fn pattern:
-- those use the GoTrue Admin API via a service-role key (server-side). The ops
-- console deliberately holds NO service-role key (9.2 decision). So provisioning
-- runs as a guarded definer fn that writes BOTH stores directly — exactly the
-- dual-store shape create-employee produces, just without GoTrue's HTTP API:
--   * auth.users (+ auth.identities) so the builder admin can sign in, and
--   * public.users with the SAME bcrypt hash (the login edge fn verifies this
--     store first, then signInWithPassword against auth.users).
-- pgcrypto bcrypt ($2a$12) is accepted by BOTH GoTrue and bcryptjs (verified).
--
-- Username handling mirrors create-employee / login EXACTLY: a plain username
-- gets the synthetic domain `@employees.nirman.local` so GoTrue accepts the row
-- and the login fn's identical synth resolves it. role='admin' passes the web gate.
--
-- Migration numbering: prod head 0089 (0090 ops_list_plans is local-only, Story 9.4).
-- This is 0091. File-based, `supabase db push --linked`. NEVER MCP apply.
-- (Story 9.5 is FREE/LOCAL — applied to the local Docker stack only, NOT pushed.)

BEGIN;

CREATE OR REPLACE FUNCTION public.provision_tenant(
  p_builder_name   text,
  p_admin_username text,
  p_admin_password text,
  p_admin_name     text    DEFAULT NULL,
  p_plan_id        uuid    DEFAULT NULL,
  p_start          text    DEFAULT 'trial',   -- 'trial' | 'paid'
  p_amount_inr     integer DEFAULT NULL,      -- required when p_start='paid'
  p_method         text    DEFAULT NULL,      -- required when p_start='paid'
  p_timezone       text    DEFAULT 'Asia/Kolkata'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth
AS $$
DECLARE
  v_tenant_id uuid := extensions.gen_random_uuid();
  v_user_id   uuid := extensions.gen_random_uuid();
  v_username  text;
  v_hash      text;
  v_status    public.tenant_status;
  v_renew     jsonb;
BEGIN
  -- 1. Guard — the ONE authority check (fail-closed for a non-platform-admin).
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  -- 2. Validate inputs.
  IF coalesce(btrim(p_builder_name), '') = '' THEN
    RAISE EXCEPTION 'builder_name_required' USING ERRCODE = '22023';
  END IF;
  IF coalesce(btrim(p_admin_username), '') = '' THEN
    RAISE EXCEPTION 'admin_username_required' USING ERRCODE = '22023';
  END IF;
  IF length(coalesce(p_admin_password, '')) < 8 THEN
    RAISE EXCEPTION 'weak_password' USING ERRCODE = '22023';
  END IF;
  IF p_start NOT IN ('trial', 'paid') THEN
    RAISE EXCEPTION 'invalid_start' USING ERRCODE = '22023';
  END IF;
  IF p_start = 'paid' AND (p_plan_id IS NULL OR p_amount_inr IS NULL OR p_method IS NULL) THEN
    RAISE EXCEPTION 'paid_start_needs_plan_amount_method' USING ERRCODE = '22023';
  END IF;

  -- 3. Normalize the username the SAME way create-employee / login do, so the
  --    provisioned admin can sign in with the plain handle.
  v_username := lower(btrim(p_admin_username));
  IF position('@' in v_username) = 0 THEN
    v_username := v_username || '@employees.nirman.local';
  END IF;

  -- Global uniqueness (login looks up by email_or_username, not tenant-scoped).
  IF EXISTS (SELECT 1 FROM public.users WHERE lower(email_or_username) = v_username)
     OR EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = v_username) THEN
    RAISE EXCEPTION 'username_taken' USING ERRCODE = '23505';
  END IF;

  -- 4. One bcrypt hash for BOTH stores ($2a$12 — GoTrue + bcryptjs compatible).
  v_hash := extensions.crypt(p_admin_password, extensions.gen_salt('bf', 12));

  -- 5. Create the tenant (starts 'trial'; a paid start is flipped by renew_tenant
  --    below so the ledger + paid_until go through the single 9.1 seam).
  INSERT INTO public.tenants (id, name, timezone, status)
  VALUES (v_tenant_id, btrim(p_builder_name), coalesce(nullif(btrim(p_timezone), ''), 'Asia/Kolkata'), 'trial');

  -- For a trial start, record the chosen plan (optional) without a paid window.
  IF p_start = 'trial' AND p_plan_id IS NOT NULL THEN
    UPDATE public.tenants SET plan_id = p_plan_id WHERE id = v_tenant_id;
  END IF;

  -- 6. First admin — dual store. auth.users (GoTrue token varchars MUST be '' not
  --    NULL) + auth.identities, then public.users with the same id + hash.
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous,
    confirmation_token, recovery_token, email_change,
    email_change_token_new, email_change_token_current,
    phone_change, phone_change_token, reauthentication_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', v_user_id,
    'authenticated', 'authenticated', v_username, v_hash,
    now(), now(), now(),
    jsonb_build_object('provider','email','providers',jsonb_build_array('email'),
                       'role','admin','tenant_id',v_tenant_id::text),
    jsonb_build_object('full_name', p_admin_name),
    false, false,
    '', '', '', '', '', '', '', ''
  );

  INSERT INTO auth.identities (
    id, user_id, provider_id, provider, identity_data,
    last_sign_in_at, created_at, updated_at
  ) VALUES (
    extensions.gen_random_uuid(), v_user_id, v_user_id::text, 'email',
    jsonb_build_object('sub', v_user_id::text, 'email', v_username, 'email_verified', true),
    now(), now(), now()
  );

  INSERT INTO public.users (
    id, tenant_id, role, email_or_username, bcrypt_password_hash,
    must_change_password, is_active
  ) VALUES (
    v_user_id, v_tenant_id, 'admin', v_username, v_hash, true, true
  );

  -- 7. Paid start: run the payment through the single 9.1 seam (flips active,
  --    sets paid_until, writes the ledger row stamped with the operator).
  IF p_start = 'paid' THEN
    v_renew := public.renew_tenant(v_tenant_id, p_plan_id, p_amount_inr, p_method, 'initial provision');
  END IF;

  SELECT status INTO v_status FROM public.tenants WHERE id = v_tenant_id;

  -- 8. Audit — permanent record of who provisioned whom. NEVER store the password.
  INSERT INTO public.ops_audit_log (actor_user_id, action, target_tenant_id, detail)
  VALUES (
    auth.uid(), 'provision_tenant', v_tenant_id,
    jsonb_build_object(
      'builder_name', btrim(p_builder_name),
      'admin_user_id', v_user_id,
      'admin_username', v_username,
      'plan_id', p_plan_id,
      'start', p_start,
      'amount_inr', p_amount_inr,
      'method', p_method
    )
  );

  RETURN jsonb_build_object(
    'tenant_id',      v_tenant_id,
    'admin_user_id',  v_user_id,
    'admin_username', v_username,
    'status',         v_status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.provision_tenant(text, text, text, text, uuid, text, integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.provision_tenant(text, text, text, text, uuid, text, integer, text, text) TO authenticated;

COMMENT ON FUNCTION public.provision_tenant(text, text, text, text, uuid, text, integer, text, text) IS
  'Story 9.5 — platform-admin-guarded provisioning of a NEW builder: creates the tenant + first admin (dual-store auth.users/identities + public.users, synthetic @employees.nirman.local username, one bcrypt hash for both, must_change_password=true), optional trial or paid start (paid delegates to renew_tenant), audit-logged. RLS-native, NO service-role. Returns {tenant_id, admin_user_id, admin_username, status}. Password is NEVER persisted in the audit detail.';

COMMIT;
