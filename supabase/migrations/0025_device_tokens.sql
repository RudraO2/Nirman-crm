-- Story 3.6 — device_tokens for push notification delivery
-- Stores FCM tokens keyed by (user_id, token) — one user can have multiple devices.
-- upsert_fcm_token(): called from app on init / token refresh.
-- Roll-forward only. Never edit after apply.

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id          uuid        PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  user_id     uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  tenant_id   uuid        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  token       text        NOT NULL,
  platform    text,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, token)
);

COMMENT ON TABLE public.device_tokens IS
  'Story 3.6 — FCM device tokens per user. Upserted on app init / token refresh.';

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_tokens FORCE  ROW LEVEL SECURITY;

-- Users can only read/write their own tokens
CREATE POLICY device_tokens_own
  ON public.device_tokens
  FOR ALL TO authenticated
  USING      (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.device_tokens TO authenticated;

CREATE INDEX IF NOT EXISTS device_tokens_user_id_idx
  ON public.device_tokens (user_id);

-- ── upsert_fcm_token ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.upsert_fcm_token(
  p_token    text,
  p_platform text DEFAULT 'android'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  INSERT INTO public.device_tokens (user_id, tenant_id, token, platform, updated_at)
  VALUES (
    auth.uid(),
    public.auth_tenant_id(),
    p_token,
    p_platform,
    now()
  )
  ON CONFLICT (user_id, token)
    DO UPDATE SET platform   = EXCLUDED.platform,
                  updated_at = now();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.upsert_fcm_token(text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.upsert_fcm_token(text, text) TO   authenticated;
