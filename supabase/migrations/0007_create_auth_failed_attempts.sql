-- Story 1.7 — Login rate limiting and lockout
-- FRs: FR-38 (login rate limiting, 5 fails → 15-min lockout)
-- NFRs: NFR-9 (bcrypt constant-time), NFR-5 (HTTPS/TLS)
--
-- Reconstructed from live DB state (2026-05-27) — applied to cloud but file was missing locally.
-- Roll-forward only. Never edit after apply.

-- ────────────────────────────────────────────────────────────────────────────
-- Add locked_until to users
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP WITH TIME ZONE;

-- ────────────────────────────────────────────────────────────────────────────
-- Add account_unlocked to user_event_type enum
-- ────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    WHERE t.typname = 'user_event_type' AND e.enumlabel = 'account_unlocked'
  ) THEN
    ALTER TYPE public.user_event_type ADD VALUE 'account_unlocked';
  END IF;
END
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- auth_failed_attempts table
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.auth_failed_attempts (
  id           uuid        NOT NULL DEFAULT extensions.gen_random_uuid(),
  tenant_id    uuid        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id      uuid        REFERENCES public.users(id) ON DELETE SET NULL,
  attempted_at timestamptz NOT NULL DEFAULT now(),
  ip_address   text,
  outcome      text        NOT NULL
    CONSTRAINT auth_failed_attempts_outcome_check
      CHECK (outcome IN ('failed_credentials', 'unknown_user', 'locked', 'success')),
  PRIMARY KEY (id)
);

COMMENT ON TABLE public.auth_failed_attempts IS
  'Story 1.7 — Append-only login attempt log. Service-role writes; admin-role reads own tenant.';

-- ────────────────────────────────────────────────────────────────────────────
-- Indexes
-- ────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_auth_failed_user_time
  ON public.auth_failed_attempts (user_id, attempted_at)
  WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_auth_failed_tenant_time
  ON public.auth_failed_attempts (tenant_id, attempted_at DESC);

-- ────────────────────────────────────────────────────────────────────────────
-- RLS
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.auth_failed_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auth_failed_attempts FORCE  ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admins_read_own_tenant_attempts ON public.auth_failed_attempts;
CREATE POLICY admins_read_own_tenant_attempts ON public.auth_failed_attempts
  FOR SELECT
  TO authenticated
  USING (
    tenant_id = ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid
    AND ((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin'
  );

-- Service role (Edge Functions) handles all writes — no INSERT/UPDATE/DELETE policy needed for authenticated.
GRANT SELECT ON public.auth_failed_attempts TO authenticated;
