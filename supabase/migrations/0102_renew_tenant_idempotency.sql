-- 0102_renew_tenant_idempotency.sql
-- Robustness audit 2026-07-11, finding H6 (HIGH — flagged by both the
-- concurrency and ops lenses).
--
-- renew_tenant()'s FOR UPDATE lock prevents lost updates but not a SECOND
-- sequential call: a double-click or client retry on "Record Payment"
-- created a second ledger row and double-extended paid_until for one real
-- collection.
--
-- Fix inside the single 9.1 seam (covers ops_renew_tenant, provision_tenant
-- paid-start, and the future Razorpay webhook alike): after taking the
-- tenant lock, an IDENTICAL payment (same tenant/plan/amount/method/
-- operator) recorded within the last 60 seconds is treated as the same
-- collection — the existing row is returned, nothing is inserted or
-- extended. Two deliberate identical collections minutes apart still both
-- record. Because the tenant row is locked first, two racing calls
-- serialize and the second one sees the first's ledger row.
--
-- Return shape is unchanged ({tenant_id,status,paid_until,payment_id});
-- a deduped call additionally carries "deduplicated": true.

BEGIN;

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
  v_existing        RECORD;
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

  -- Audit H6 (0102): idempotency window — an identical payment recorded by
  -- the same operator within 60s is the same physical collection (double
  -- click / client retry). Return it instead of double-charging the ledger.
  SELECT id INTO v_existing
    FROM public.tenant_payments
   WHERE tenant_id   = p_tenant_id
     AND plan_id     = p_plan_id
     AND amount_inr  = p_amount_inr
     AND method      = p_method
     AND recorded_by IS NOT DISTINCT FROM auth.uid()
     AND created_at  > now() - interval '60 seconds'
   ORDER BY created_at DESC
   LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'tenant_id',    p_tenant_id,
      'status',       v_tenant.status,
      'paid_until',   v_tenant.paid_until,
      'payment_id',   v_existing.id,
      'deduplicated', true
    );
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

COMMENT ON FUNCTION public.renew_tenant(uuid, uuid, integer, text, text) IS
  'Story 9.1 + 0102 (audit H6) — the ONE billing seam (service-role only). Records a payment in tenant_payments, extends tenants.paid_until (stacks from the later of paid_until/now), sets plan_id, flips status->active. Idempotent over a 60s window for identical (tenant,plan,amount,method,operator) calls — a double-click/retry returns the existing row (deduplicated:true) instead of double-extending. Manual ops (9.2) + future Razorpay both call this.';

COMMIT;
