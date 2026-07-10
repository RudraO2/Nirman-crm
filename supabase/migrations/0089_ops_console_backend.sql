-- 0089_ops_console_backend.sql
-- Story 9.2 (Epic 9) — Platform-admin ops backend: the audited, guarded operations
-- seam the super-admin ops console (UI = 9.3) drives. Cross-tenant surface.
--
-- Builds on Story 9.1 (0088: plans, tenant_payments, renew_tenant(), get_my_billing_status()).
-- This migration is the WHOLE story 9.2 (DB layer only — NO UI, NO edge fn, NO MFA):
--   1. platform_admins  — cross-tenant allowlist of founder/operator user_ids (deny-all RLS).
--   2. ops_audit_log    — append-only, immutable audit trail (deny-all RLS).
--   3. is_platform_admin() — the single guard predicate (auth.uid() ∈ platform_admins).
--   4. ops_renew_tenant()  — JWT-guarded doorway that DELEGATES to the 9.1 renew_tenant()
--                            seam + writes an audit row. No renew logic re-implemented here.
--   5. ops_suspend_tenant() / ops_reactivate_tenant() — guarded status flips + audit.
--   6. ops_list_tenants() / ops_list_tenant_payments() / ops_list_audit() — guarded
--                            CROSS-TENANT reads for the console (all tenants / one ledger / audit).
--
-- ARCHITECTURE (locked, Story 9.2): RLS-native, NO service-role key in any client. The ops
-- app (9.3) signs in a platform-admin user via Supabase auth and calls these RPCs with that
-- JWT. Guard + audit live IN the database (can't be bypassed by a client). The future Razorpay
-- webhook keeps calling the raw service-role renew_tenant() directly — zero rework.
--
-- CRITICAL: these reads are DELIBERATELY cross-tenant (they never use auth_tenant_id()). That
-- is legitimate ONLY because is_platform_admin() gates every one. Do NOT "fix" them to scope
-- by auth_tenant_id() — the platform admin belongs to no tenant and the console would break.
--
-- ops_renew_tenant DELEGATES to public.renew_tenant (service-role-only). A SECURITY DEFINER fn
-- owned by the migration runner (postgres) executes it via implicit owner rights, so the
-- service-role-only GRANT is not an obstacle. auth.uid() inside renew_tenant still resolves to
-- the platform admin (SECURITY DEFINER changes role, not the request.jwt.claims GUC), so
-- tenant_payments.recorded_by is correctly stamped with the operator who recorded the payment.
--
-- Migration numbering: prod head 0086; 0087 reserved by Story 8.3 (harden-edge-function-auth,
-- in-review); 0088 = Story 9.1. This is 0089. Run `supabase migration list` before adding.
-- File-based migration, applied via `supabase db push --linked`. NEVER MCP apply.

BEGIN;

-- 1. platform_admins — cross-tenant operator allowlist -----------------------------------------
--    Plain-uuid PK (holds an auth.users id), NO FK to auth.users — mirrors
--    tenant_payments.recorded_by (0088), so the slice is testable on the local stack without
--    provisioning GoTrue rows. NOT tenant-scoped: a platform admin acts across ALL tenants.
CREATE TABLE IF NOT EXISTS public.platform_admins (
  user_id    uuid PRIMARY KEY,
  note       text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.platform_admins IS
  'Story 9.2 — cross-tenant allowlist of platform-admin (founder/operator) auth.users ids. NOT tenant-scoped. Deny-all RLS; reached only via is_platform_admin(). Seeded post-deploy by the operator (INSERT their own auth.uid()).';

-- 2. ops_audit_log — append-only immutable trail ----------------------------------------------
--    Plain-uuid target/actor (no FK) so an audit row is PERMANENT even if a tenant is later
--    hard-deleted. Only writer = the SECURITY DEFINER ops fns (INSERT); only reader = ops_list_audit().
CREATE TABLE IF NOT EXISTS public.ops_audit_log (
  id              uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  seq             bigint GENERATED ALWAYS AS IDENTITY,  -- monotonic insertion order for a deterministic browse
  actor_user_id   uuid,
  action          text NOT NULL,
  target_tenant_id uuid,
  detail          jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Browse orders by seq (not created_at): created_at = now() is TRANSACTION-START time, so two
-- audit rows written in one transaction share it and would tie; seq is strictly monotonic, so
-- the newest-first browse is deterministic and reflects true insertion order.
CREATE INDEX IF NOT EXISTS ops_audit_log_seq_idx
  ON public.ops_audit_log (seq DESC);

COMMENT ON TABLE public.ops_audit_log IS
  'Story 9.2 — append-only, immutable platform-ops audit trail. One row per privileged ops action (renew/suspend/reactivate). Deny-all RLS; written only by SECURITY DEFINER ops fns, read only via ops_list_audit(). Plain-uuid target/actor (no FK) so rows survive tenant hard-delete — audit is permanent.';

-- 3. RLS: deny-all FORCE on both tables (mirrors 0088 plans/tenant_payments) -------------------
ALTER TABLE public.platform_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_admins FORCE  ROW LEVEL SECURITY;
ALTER TABLE public.ops_audit_log   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ops_audit_log   FORCE  ROW LEVEL SECURITY;
-- No policies for anon/authenticated on purpose: no direct access.

REVOKE ALL ON public.platform_admins FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.ops_audit_log   FROM PUBLIC, anon, authenticated;

-- 4. is_platform_admin() — the single guard predicate -----------------------------------------
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.platform_admins WHERE user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_platform_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated;

COMMENT ON FUNCTION public.is_platform_admin() IS
  'Story 9.2 — the ONE platform-admin guard: true iff auth.uid() is in platform_admins. NULL auth.uid() (no JWT / service-role) -> false -> fail-closed. Called as the first line of every ops_* fn.';

-- 5. ops_renew_tenant() — guarded doorway that DELEGATES to the 9.1 seam -----------------------
CREATE OR REPLACE FUNCTION public.ops_renew_tenant(
  p_tenant_id  uuid,
  p_plan_id    uuid,
  p_amount_inr integer,
  p_method     text,
  p_note       text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  -- delegate to the single 9.1 seam: all locking / stacking / reactivation lives there.
  v_result := public.renew_tenant(p_tenant_id, p_plan_id, p_amount_inr, p_method, p_note);

  INSERT INTO public.ops_audit_log (actor_user_id, action, target_tenant_id, detail)
  VALUES (
    auth.uid(), 'renew_tenant', p_tenant_id,
    jsonb_build_object(
      'plan_id',    p_plan_id,
      'amount_inr', p_amount_inr,
      'method',     p_method,
      'note',       p_note,
      'result',     v_result
    )
  );

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.ops_renew_tenant(uuid, uuid, integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_renew_tenant(uuid, uuid, integer, text, text) TO authenticated;

COMMENT ON FUNCTION public.ops_renew_tenant(uuid, uuid, integer, text, text) IS
  'Story 9.2 — platform-admin-guarded doorway to the 9.1 renew_tenant() seam. Guards via is_platform_admin(), delegates (no renew logic duplicated), writes an ops_audit_log row, returns the seam jsonb. recorded_by = the operator''s auth.uid(). Future Razorpay bypasses this and calls renew_tenant directly as service_role.';

-- 6. ops_suspend_tenant() ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ops_suspend_tenant(
  p_tenant_id uuid,
  p_reason    text DEFAULT NULL
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

  UPDATE public.tenants SET status = 'suspended' WHERE id = p_tenant_id;

  INSERT INTO public.ops_audit_log (actor_user_id, action, target_tenant_id, detail)
  VALUES (auth.uid(), 'suspend_tenant', p_tenant_id,
          jsonb_build_object('prev_status', v_prev, 'reason', p_reason));

  RETURN jsonb_build_object('tenant_id', p_tenant_id, 'status', 'suspended');
END;
$$;

REVOKE ALL ON FUNCTION public.ops_suspend_tenant(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_suspend_tenant(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.ops_suspend_tenant(uuid, text) IS
  'Story 9.2 — platform-admin-guarded suspend. Flips tenants.status -> suspended (cutoff via the existing 0056 auth_tenant_id gate), audit-logged with prev_status + reason. Idempotent-safe. Returns {tenant_id,status}.';

-- 7. ops_reactivate_tenant() ------------------------------------------------------------------
--    Manual restore that does NOT touch paid_until (may precede payment; renew_tenant is the
--    paid path). Access restored purely by the status flip.
--    SCOPE CAVEAT (F2): this is the "undo an erroneous/manual suspension" op, valid for a
--    tenant whose paid_until is in the FUTURE or NULL. Reactivating a genuinely LAPSED tenant
--    (paid_until < now(), non-null) only holds until the next hourly expire_lapsed_tenants()
--    sweep re-suspends it. To restore a lapsed tenant, RENEW (ops_renew_tenant extends
--    paid_until AND flips active) — do not reactivate. A dedicated comp/grace op is future work.
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
  'Story 9.2 — platform-admin-guarded manual reactivate (undo an erroneous/manual suspension). Flips tenants.status -> active WITHOUT touching paid_until. For a tenant whose paid_until is future/NULL; a genuinely LAPSED tenant (paid_until<now, non-null) is re-suspended by the hourly sweep, so use ops_renew_tenant to restore a lapsed tenant. Audit-logged with prev_status + note. Returns {tenant_id,status}.';

-- 8. ops_list_tenants() — cross-tenant triage list --------------------------------------------
CREATE OR REPLACE FUNCTION public.ops_list_tenants()
RETURNS TABLE (
  tenant_id      uuid,
  name           text,
  status         public.tenant_status,
  plan_name      text,
  paid_until     timestamptz,
  days_remaining integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT t.id, t.name, t.status, p.name AS plan_name, t.paid_until,
           CASE WHEN t.paid_until IS NULL THEN NULL
                ELSE ceil(extract(epoch FROM (t.paid_until - now())) / 86400.0)::int
           END AS days_remaining
      FROM public.tenants t
      LEFT JOIN public.plans p ON p.id = t.plan_id
     ORDER BY t.paid_until ASC NULLS LAST, t.name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.ops_list_tenants() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_list_tenants() TO authenticated;

COMMENT ON FUNCTION public.ops_list_tenants() IS
  'Story 9.2 — platform-admin-guarded CROSS-TENANT list (the console triage home). Returns every tenant with status, plan, paid_until, days_remaining, soonest-to-lapse first. Deliberately NOT scoped by auth_tenant_id() — legitimate only because is_platform_admin() gates it.';

-- 9. ops_list_tenant_payments() — one tenant's ledger -----------------------------------------
CREATE OR REPLACE FUNCTION public.ops_list_tenant_payments(p_tenant_id uuid)
RETURNS SETOF public.tenant_payments
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT * FROM public.tenant_payments
     WHERE tenant_id = p_tenant_id
     ORDER BY paid_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.ops_list_tenant_payments(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_list_tenant_payments(uuid) TO authenticated;

COMMENT ON FUNCTION public.ops_list_tenant_payments(uuid) IS
  'Story 9.2 — platform-admin-guarded per-tenant payment ledger (newest paid_at first). The ledger is otherwise unreachable (deny-all RLS on tenant_payments).';

-- 10. ops_list_audit() — global immutable audit browse ----------------------------------------
CREATE OR REPLACE FUNCTION public.ops_list_audit(
  p_limit  integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS SETOF public.ops_audit_log
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_limit  int := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT * FROM public.ops_audit_log
     ORDER BY seq DESC
     OFFSET v_offset
     LIMIT  v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.ops_list_audit(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_list_audit(integer, integer) TO authenticated;

COMMENT ON FUNCTION public.ops_list_audit(integer, integer) IS
  'Story 9.2 — platform-admin-guarded global audit browse, newest first by monotonic seq (deterministic even for same-transaction rows), limit clamped 1..500. The ops_audit_log is otherwise unreachable (deny-all RLS).';

COMMIT;
