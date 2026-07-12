-- 0106_reactivate_cancelled_guard.sql
-- Robustness-audit 2026-07-11 LOW: ops_reactivate_tenant flipped ANY non-active tenant —
-- including a genuinely CANCELLED one — straight to active with no paid window. Reactivate is
-- the "undo an erroneous/manual suspension" op (0089 F2 caveat); reviving a cancelled tenant
-- is a commercial decision that must go through the paid path (ops_renew_tenant already flips
-- cancelled -> active AND sets a real paid_until). Now: prev_status = 'cancelled' -> P0001
-- 'tenant_cancelled_use_renew'. Body otherwise identical to 0089. Same signature, roll-forward.
-- File-based migration; never MCP apply.

BEGIN;

CREATE OR REPLACE FUNCTION public.ops_reactivate_tenant(
  p_tenant_id uuid,
  p_note      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_prev public.tenant_status;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_prev
    FROM public.tenants
   WHERE id = p_tenant_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tenant_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- audit-0106: a cancelled tenant is revived only by recording a payment
  -- (renew_tenant), never by a bare status flip with no paid window.
  IF v_prev = 'cancelled' THEN
    RAISE EXCEPTION 'tenant_cancelled_use_renew: record a payment to revive a cancelled tenant'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.tenants SET status = 'active' WHERE id = p_tenant_id;

  INSERT INTO public.ops_audit_log (actor_user_id, action, target_tenant_id, detail)
  VALUES (auth.uid(), 'reactivate_tenant', p_tenant_id,
          jsonb_build_object('prev_status', v_prev, 'note', p_note));

  RETURN jsonb_build_object('tenant_id', p_tenant_id, 'status', 'active');
END;
$$;

REVOKE ALL ON FUNCTION public.ops_reactivate_tenant(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_reactivate_tenant(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.ops_reactivate_tenant(uuid, text) IS
  'Story 9.2 + audit-0106 — platform-admin-guarded manual reactivate (undo an erroneous/manual suspension). Flips tenants.status -> active WITHOUT touching paid_until. REJECTS cancelled tenants (tenant_cancelled_use_renew) — revive those via ops_renew_tenant. Lapsed tenants are re-suspended by the hourly sweep, so renew those too. Audit-logged with prev_status + note.';

COMMIT;
