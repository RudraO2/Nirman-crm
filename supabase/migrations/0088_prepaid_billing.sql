-- 0088_prepaid_billing.sql
-- Story 9.1 (Epic 9) — Prepaid access-gating seam. Supersedes the abandoned
-- "Stripe per-seat" design (business model locked 2026-07-09: per-PROJECT monthly
-- prepaid subscription, decoupled collection, Razorpay-later). See epics.md Epic 9.
--
-- This migration is the WHOLE story 9.1 (DB seam only — NO UI, NO edge fn):
--   1. plans            — operator-set catalog (no prices hard-coded in app code).
--   2. tenant_payments  — append-style ledger of out-of-band collections.
--   3. tenants.plan_id + tenants.paid_until — the prepaid window.
--   4. renew_tenant()          — the ONE seam (service-role): record a payment,
--                                extend paid_until, reactivate. Manual now; future
--                                Razorpay webhook calls the SAME fn (zero rework).
--   5. expire_lapsed_tenants() — hourly pg_cron sweep: active + lapsed -> suspended,
--                                so the EXISTING auth_tenant_id() gate (0056) cuts off
--                                access at the data layer. No new RLS surface.
--   6. get_my_billing_status() — tenant-admin read for the recharge screen. Bypasses
--                                auth_tenant_id() ON PURPOSE (it returns NULL when
--                                suspended, which is exactly when the screen must show).
--
-- Access model: access is gated purely on tenants.status via auth_tenant_id() (0056).
-- This migration NEVER modifies auth_tenant_id(); it only flips status.
--
-- CRITICAL invariant: expire_lapsed_tenants MUST exclude paid_until IS NULL, else it
-- would suspend the live V1 prod tenant (active, paid_until NULL — 0056 backfill) and
-- every trial. Trials are governed by trial_ends_at (8.2), out of scope here.
--
-- File-based migration, applied via `supabase db push --linked`. NEVER MCP apply.

BEGIN;

-- 1. plans -----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.plans (
  id              uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  name            text    NOT NULL,
  price_inr       integer NOT NULL DEFAULT 0 CHECK (price_inr >= 0),
  interval_months integer NOT NULL DEFAULT 1 CHECK (interval_months > 0),
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.plans IS
  'Story 9.1 — operator-set subscription plan catalog. Amounts live here (price_inr), NOT hard-coded in app code. Deny-all RLS; reached via SECURITY DEFINER fns + service_role only.';

-- 2. tenant_payments ledger ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tenant_payments (
  id           uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id    uuid    NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  plan_id      uuid    NOT NULL REFERENCES public.plans(id)   ON DELETE RESTRICT,
  amount_inr   integer NOT NULL CHECK (amount_inr >= 0),
  method       text    NOT NULL CHECK (method IN ('upi','cash','bank_transfer','razorpay','comp','other')),
  paid_at      timestamptz NOT NULL DEFAULT now(),
  covers_from  timestamptz NOT NULL,
  covers_until timestamptz NOT NULL,
  recorded_by  uuid,
  note         text,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS tenant_payments_tenant_paid_idx
  ON public.tenant_payments (tenant_id, paid_at DESC);

COMMENT ON TABLE public.tenant_payments IS
  'Story 9.1 — ledger of out-of-band collections (UPI/cash/bank/razorpay). One row per renew_tenant() call. Deny-all RLS; ledger never exposed to tenant apps.';

-- 3. tenants prepaid columns -----------------------------------------------------------------
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS plan_id    uuid REFERENCES public.plans(id),
  ADD COLUMN IF NOT EXISTS paid_until timestamptz;

COMMENT ON COLUMN public.tenants.paid_until IS
  'Story 9.1 — prepaid window end. NULL = never enrolled in prepaid billing (live V1 tenant + trials); such rows are NEVER auto-suspended. When non-NULL and < now(), expire_lapsed_tenants() flips status active->suspended.';
COMMENT ON COLUMN public.tenants.plan_id IS
  'Story 9.1 — the plan the tenant is currently subscribed to (set by renew_tenant()).';

-- 4. RLS: deny-all on the two operator tables (FORCE, mirroring builder-ops convention) -------
--    SECURITY DEFINER fns (owner has BYPASSRLS) and service_role still read/write freely.
ALTER TABLE public.plans           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plans           FORCE  ROW LEVEL SECURITY;
ALTER TABLE public.tenant_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_payments FORCE  ROW LEVEL SECURITY;
-- No policies for authenticated/anon on purpose: no direct access.

REVOKE ALL ON public.plans           FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.tenant_payments FROM PUBLIC, anon, authenticated;

-- 5. renew_tenant() — the single seam (service-role only) ------------------------------------
CREATE OR REPLACE FUNCTION public.renew_tenant(
  p_tenant_id uuid,
  p_plan_id   uuid,
  p_amount_inr integer,
  p_method    text,
  p_note      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant          RECORD;
  v_interval_months int;
  v_covers_from     timestamptz;
  v_covers_until    timestamptz;
  v_payment_id      uuid;
BEGIN
  -- lock the tenant so concurrent renewals can't race on paid_until
  SELECT id, status, paid_until
    INTO v_tenant
    FROM public.tenants
   WHERE id = p_tenant_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tenant_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT interval_months
    INTO v_interval_months
    FROM public.plans
   WHERE id = p_plan_id AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'plan_not_found_or_inactive' USING ERRCODE = 'P0002';
  END IF;

  -- stack from the later of current paid_until or now(): an early renewal never
  -- shortens prepaid time; a post-lapse renewal starts from now().
  v_covers_from  := greatest(COALESCE(v_tenant.paid_until, now()), now());
  v_covers_until := v_covers_from + make_interval(months => v_interval_months);

  INSERT INTO public.tenant_payments
    (tenant_id, plan_id, amount_inr, method, covers_from, covers_until, recorded_by, note)
  VALUES
    (p_tenant_id, p_plan_id, p_amount_inr, p_method, v_covers_from, v_covers_until, auth.uid(), p_note)
  RETURNING id INTO v_payment_id;

  UPDATE public.tenants
     SET paid_until = v_covers_until,
         plan_id    = p_plan_id,
         status     = 'active'
   WHERE id = p_tenant_id;

  RETURN jsonb_build_object(
    'tenant_id',  p_tenant_id,
    'status',     'active',
    'paid_until', v_covers_until,
    'payment_id', v_payment_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.renew_tenant(uuid, uuid, integer, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.renew_tenant(uuid, uuid, integer, text, text) TO service_role;

COMMENT ON FUNCTION public.renew_tenant(uuid, uuid, integer, text, text) IS
  'Story 9.1 — the ONE billing seam (service-role only). Records a payment in tenant_payments, extends tenants.paid_until (stacks from the later of paid_until/now), sets plan_id, flips status->active. Manual ops (9.2) + future Razorpay both call this. Returns {tenant_id,status,paid_until,payment_id}.';

-- 6. expire_lapsed_tenants() — hourly pg_cron sweep (service-role only) ----------------------
--    Modeled on release_expired_holds() (0077): bounded, TOCTOU-safe, re-assert in UPDATE.
CREATE OR REPLACE FUNCTION public.expire_lapsed_tenants()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_t     RECORD;
  v_count int := 0;
BEGIN
  FOR v_t IN
    SELECT id
    FROM   public.tenants
    WHERE  status = 'active'
      AND  paid_until IS NOT NULL   -- NEVER touch never-enrolled tenants (live V1 + trials)
      AND  paid_until < now()
    ORDER BY paid_until
    LIMIT 500
    FOR UPDATE SKIP LOCKED
  LOOP
    -- TOCTOU re-assert: only suspend if STILL active + STILL lapsed
    UPDATE public.tenants
       SET status = 'suspended'
     WHERE id = v_t.id
       AND status = 'active'
       AND paid_until IS NOT NULL
       AND paid_until < now();
    IF NOT FOUND THEN
      CONTINUE;
    END IF;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_lapsed_tenants() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_lapsed_tenants() TO service_role;

COMMENT ON FUNCTION public.expire_lapsed_tenants() IS
  'Story 9.1 — pg_cron hourly sweep. Flips active tenants whose paid_until has passed to suspended (cutoff via auth_tenant_id gate). Excludes paid_until IS NULL (live V1 + trials). TOCTOU-safe, bounded 500. System fn (no JWT). Returns count suspended.';

-- 7. get_my_billing_status() — tenant-admin read for the recharge screen ---------------------
--    DELIBERATELY does NOT use auth_tenant_id() (which returns NULL for a suspended tenant —
--    exactly when this must render). Derives tenant id straight from the JWT claim with the
--    same UUID-format guard as auth_tenant_id (0056), and reads regardless of status.
CREATE OR REPLACE FUNCTION public.get_my_billing_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_role      text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id uuid;
  v_row       RECORD;
BEGIN
  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  -- UUID-guarded JWT tenant extraction (verbatim from auth_tenant_id 0056), WITHOUT the
  -- status filter, so a suspended tenant's admin still gets an answer.
  v_tenant_id := (
    CASE
      WHEN (auth.jwt() -> 'app_metadata') ->> 'tenant_id'
             ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      THEN ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid
      ELSE NULL
    END
  );
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'tenant_missing' USING ERRCODE = '42501';
  END IF;

  SELECT t.status, p.name AS plan_name, t.paid_until,
         CASE WHEN t.paid_until IS NULL THEN NULL
              ELSE ceil(extract(epoch FROM (t.paid_until - now())) / 86400.0)::int
         END AS days_remaining
    INTO v_row
    FROM public.tenants t
    LEFT JOIN public.plans p ON p.id = t.plan_id
   WHERE t.id = v_tenant_id;
  IF NOT FOUND THEN
    -- valid-format JWT tenant claim but no such tenant row (stale/deleted tenant):
    -- raise like the rest of the codebase (assign_lead etc.) rather than returning a
    -- null-status object a client can't distinguish from a real state.
    RAISE EXCEPTION 'tenant_missing' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'status',         v_row.status,
    'plan_name',      v_row.plan_name,
    'paid_until',     v_row.paid_until,
    'days_remaining', v_row.days_remaining
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_billing_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_billing_status() TO authenticated, service_role;

COMMENT ON FUNCTION public.get_my_billing_status() IS
  'Story 9.1 — tenant-admin read for the recharge screen. Returns {status,plan_name,paid_until,days_remaining} for the caller''s own tenant. Admin-only. Deliberately bypasses auth_tenant_id() so a SUSPENDED tenant is still readable (that is when the recharge screen shows). Own-tenant only.';

-- 8. seed one operator-editable placeholder plan (amount nominal; operator sets real price) ---
INSERT INTO public.plans (name, price_inr, interval_months, is_active)
SELECT 'Standard Monthly', 0, 1, true
WHERE NOT EXISTS (SELECT 1 FROM public.plans);

-- 9. pg_cron schedule (guarded; pg_cron present on prod, absent locally) ----------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('expire-lapsed-tenants', '0 * * * *', $cron$ SELECT public.expire_lapsed_tenants(); $cron$);
  END IF;
END $$;

COMMIT;
