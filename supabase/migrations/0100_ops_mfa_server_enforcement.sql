-- 0100_ops_mfa_server_enforcement.sql
-- Robustness audit 2026-07-11, finding H1 (HIGH).
--
-- Story 9.7 added TOTP to the ops console, but enforcement lived only in the
-- browser: verifyStepUp() re-confirms a code client-side and the ops RPCs
-- (ops_suspend_tenant / ops_reactivate_tenant / ops_renew_tenant /
-- provision_tenant) guard solely on is_platform_admin(). Anyone holding a
-- valid platform-admin JWT (stolen session, XSS, unlocked laptop) could call
-- them directly via curl with zero TOTP.
--
-- Fix at the single chokepoint every ops fn + cross-tenant read already goes
-- through: is_platform_admin() now ALSO requires the session to be AAL2
-- (GoTrue stamps `aal: aal2` into the JWT only after a real TOTP
-- challenge+verify — exactly what the 9.7 login flow performs) WHENEVER the
-- caller has a verified TOTP factor enrolled.
--
-- Bootstrap semantics (deliberate, mirrors the 9.7 "lockout only if MFA
-- explicitly OFF" note): a platform admin with NO verified TOTP factor is
-- still admitted at AAL1 — otherwise the founder could never enroll. The
-- moment a factor is verified, AAL1 JWTs are refused server-side.
--
-- The client-side fresh-code prompt (verifyStepUp) stays what it always was:
-- a presence proof for the most destructive actions, not the authz boundary.

BEGIN;

CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
           SELECT 1 FROM public.platform_admins WHERE user_id = auth.uid()
         )
     AND (
           -- No verified TOTP factor yet -> AAL1 admitted (enrollment bootstrap).
           NOT EXISTS (
             SELECT 1
               FROM auth.mfa_factors f
              WHERE f.user_id     = auth.uid()
                AND f.factor_type = 'totp'
                AND f.status      = 'verified'
           )
           -- Factor enrolled -> the JWT itself must prove the TOTP challenge.
           OR coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
         );
$$;

COMMENT ON FUNCTION public.is_platform_admin() IS
  'Story 9.2 + 0100 (audit H1) — the ONE platform-admin guard: true iff auth.uid() is in platform_admins AND (no verified TOTP factor yet OR JWT aal=aal2). NULL auth.uid() (no JWT / service-role) -> false -> fail-closed. A stolen AAL1 JWT can no longer drive ops RPCs once TOTP is enrolled. Called as the first line of every ops_* fn.';

COMMIT;
