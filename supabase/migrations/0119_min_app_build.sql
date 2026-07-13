-- 0119_min_app_build.sql
-- Force-update gate for the mobile app.
--
-- Problem: once the APK is on the Play Store, old installs keep talking to the
-- backend forever. If a future RPC/edge-fn change is not backward compatible,
-- those old builds break with raw errors. This gate lets the operator raise a
-- minimum supported Android build number; the app checks it at startup and
-- shows a friendly "update from Play Store" screen instead of raw failures.
--
-- Shape (mirrors the 9.6 lockout philosophy):
--   * app_version_gate  — one row per platform, deny-all RLS (0089 pattern).
--   * get_min_app_build — SECURITY DEFINER reader, granted to anon TOO: the
--     check must work on the login screen, before any session exists. Global
--     platform config — deliberately NOT tenant-scoped, so it does not touch
--     the auth_tenant_id() chokepoint and stays readable for suspended tenants.
--   * ops_set_min_app_build — platform-admin-only setter (is_platform_admin()
--     = allowlist + AAL2 per 0100), audit-logged like every ops_* fn.
--
-- Client behaviour is FAIL-OPEN (network error -> app runs normally): the gate
-- is an operator convenience, not a security boundary.
--
-- Rollout: min_build starts at 0 = gate OFF (no build is ever < 0). To force
-- an update after shipping build N: SELECT ops_set_min_app_build(N);

BEGIN;

CREATE TABLE IF NOT EXISTS public.app_version_gate (
  platform   text        PRIMARY KEY,
  min_build  integer     NOT NULL DEFAULT 0 CHECK (min_build >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.app_version_gate IS
  '0119 — minimum supported mobile build number per platform (versionCode from pubspec version x.y.z+N). Deny-all RLS; read via get_min_app_build() (anon-callable), written via ops_set_min_app_build() only. min_build = 0 means the gate is off.';

ALTER TABLE public.app_version_gate ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_version_gate FORCE  ROW LEVEL SECURITY;
REVOKE ALL ON public.app_version_gate FROM PUBLIC, anon, authenticated;

INSERT INTO public.app_version_gate (platform, min_build)
VALUES ('android', 0)
ON CONFLICT (platform) DO NOTHING;

-- Reader — anon-callable on purpose: the app checks BEFORE login, and a
-- suspended tenant's old APK must still be told to update (no tenant scope).
CREATE OR REPLACE FUNCTION public.get_min_app_build(p_platform text DEFAULT 'android')
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT coalesce(
    (SELECT min_build FROM public.app_version_gate WHERE platform = p_platform),
    0
  );
$$;

REVOKE ALL ON FUNCTION public.get_min_app_build(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_min_app_build(text) TO anon, authenticated;

COMMENT ON FUNCTION public.get_min_app_build(text) IS
  '0119 — returns the minimum supported build number for a platform (0 = gate off / unknown platform). Anon-callable: the mobile app checks at startup, before any session. Exposes a single integer of platform config — no tenant data.';

-- Setter — platform-admin only (allowlist + AAL2 via is_platform_admin, 0100).
CREATE OR REPLACE FUNCTION public.ops_set_min_app_build(
  p_min_build integer,
  p_platform  text DEFAULT 'android'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_prev integer;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF p_min_build IS NULL OR p_min_build < 0 THEN
    RAISE EXCEPTION 'invalid_min_build' USING ERRCODE = '22023';
  END IF;

  SELECT min_build INTO v_prev
    FROM public.app_version_gate
   WHERE platform = p_platform
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown_platform' USING ERRCODE = '22023';
  END IF;

  UPDATE public.app_version_gate
     SET min_build = p_min_build, updated_at = now()
   WHERE platform = p_platform;

  INSERT INTO public.ops_audit_log (actor_user_id, action, target_tenant_id, detail)
  VALUES (
    auth.uid(), 'set_min_app_build', NULL,
    jsonb_build_object('platform', p_platform, 'prev', v_prev, 'new', p_min_build)
  );

  RETURN jsonb_build_object('platform', p_platform, 'min_build', p_min_build);
END;
$$;

REVOKE ALL ON FUNCTION public.ops_set_min_app_build(integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_set_min_app_build(integer, text) TO authenticated;

COMMENT ON FUNCTION public.ops_set_min_app_build(integer, text) IS
  '0119 — platform-admin-guarded setter for the mobile force-update gate. Audit-logged (action set_min_app_build, no target tenant — platform-wide). Raise to build N only AFTER build N is live on the Play Store, or every install locks out.';

COMMIT;
