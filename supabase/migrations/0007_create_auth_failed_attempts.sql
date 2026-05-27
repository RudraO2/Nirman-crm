-- Story 1.7 — FR-38: Login rate limiting & lockout
-- Architecture Decision #15: auth_failed_attempts table + Edge Function guard before bcrypt verify
-- 5 consecutive fails in 10-min window → 15-min lockout

-- 1. Add lockout column to users
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP WITH TIME ZONE;

-- 2. Extend user_event_type enum (idempotent on re-run via IF NOT EXISTS)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'account_unlocked'
      AND enumtypid = 'public.user_event_type'::regtype
  ) THEN
    ALTER TYPE public.user_event_type ADD VALUE 'account_unlocked';
  END IF;
END
$$;

-- 3. Create auth_failed_attempts table
CREATE TABLE IF NOT EXISTS public.auth_failed_attempts (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id       UUID,       -- NULL when username not found (unknown_user outcome)
  attempted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip_address    TEXT,
  outcome       TEXT        NOT NULL CHECK (outcome IN (
                              'failed_credentials',
                              'unknown_user',
                              'locked',
                              'success'
                            ))
);

-- RLS: admins can read for their tenant; service role writes bypass RLS
ALTER TABLE public.auth_failed_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admins_read_own_tenant_attempts"
  ON public.auth_failed_attempts
  FOR SELECT
  USING (
    tenant_id = ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid
    AND ((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin'
  );

-- Indexes
CREATE INDEX IF NOT EXISTS idx_auth_failed_user_time
  ON public.auth_failed_attempts (user_id, attempted_at)
  WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_auth_failed_tenant_time
  ON public.auth_failed_attempts (tenant_id, attempted_at DESC);
