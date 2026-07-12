-- 0103_demo_requests.sql
-- Robustness audit 2026-07-11, finding H10 (HIGH).
--
-- The marketing site's ONLY lead-capture form ("Book a demo" — the target of
-- every CTA on the page) had no onSubmit/action: every prospect who submitted
-- lost their info silently. This table is the capture target: the marketing
-- footer form POSTs {email} straight to PostgREST with the anon key
-- (Prefer: return=minimal, so no SELECT is needed).
--
-- Access model:
--   * anon/authenticated: INSERT (email, source) ONLY. No SELECT/UPDATE/
--     DELETE — a scraper cannot read captured emails back.
--   * founder: ops_list_demo_requests(), guarded by is_platform_admin()
--     (which since 0100 also demands AAL2 once TOTP is enrolled).
--
-- Spam is accepted as a triage problem (no captcha on V1); the CHECKs keep
-- rows bounded.

BEGIN;

CREATE TABLE IF NOT EXISTS public.demo_requests (
  id         uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  email      text NOT NULL CHECK (length(btrim(email)) BETWEEN 3 AND 200),
  source     text NOT NULL DEFAULT 'marketing_footer' CHECK (length(source) <= 40),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS demo_requests_created_idx
  ON public.demo_requests (created_at DESC);

ALTER TABLE public.demo_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_requests FORCE  ROW LEVEL SECURITY;

DROP POLICY IF EXISTS demo_requests_public_insert ON public.demo_requests;
CREATE POLICY demo_requests_public_insert ON public.demo_requests
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

GRANT INSERT (email, source) ON public.demo_requests TO anon, authenticated;

COMMENT ON TABLE public.demo_requests IS
  '0103 (audit H10) — demo requests captured by the marketing footer form. Write-only for anon (INSERT email/source); read via ops_list_demo_requests() only.';

-- Founder read path --------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ops_list_demo_requests(p_limit int DEFAULT 200)
RETURNS SETOF public.demo_requests
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT *
    FROM public.demo_requests
   WHERE public.is_platform_admin()
   ORDER BY created_at DESC
   LIMIT greatest(1, least(coalesce(p_limit, 200), 1000));
$$;

REVOKE ALL ON FUNCTION public.ops_list_demo_requests(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_list_demo_requests(int) TO authenticated;

COMMENT ON FUNCTION public.ops_list_demo_requests(int) IS
  '0103 — newest-first demo-request browse for the ops console. Empty (not error) for non-platform-admins via the WHERE guard.';

COMMIT;
