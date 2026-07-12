-- 0115_tenant_uses_inventory.sql
-- Progressive disclosure (ux-progressive-disclosure.md §1) — the tenant-usage signal.
--
-- tenant_uses_inventory = "this tenant has EVER had a project". One canonical,
-- server-truth check consumed by the admin sidebar Inventory gate and the mobile
-- You-tab Availability / Booking dashboard / Amendments gates.
--
-- Behavioral contract (non-negotiable, §1 "Flip OFF: never"): OFF→ON only. A live
-- EXISTS(projects) query would flip back to false if the last project is deleted,
-- so the signal is a persisted one-way marker: tenants.inventory_first_used_at is
-- stamped once by an AFTER INSERT trigger on projects and never cleared.
--
--   * Backfill: tenants that already have projects get their earliest
--     project.created_at (existing tenants unfold immediately, honestly dated).
--   * Trigger fn is SECURITY DEFINER — the inserting rep/admin has no UPDATE
--     grant on tenants (0003), and tenants is FORCE RLS; same pattern as
--     auth_tenant_id (0056) / _seed_starter_whatsapp_templates (0108).
--   * RPC tenant_uses_inventory() — any authenticated tenant member may read it
--     (mobile Availability is role-agnostic). Tenant id is UUID-guarded straight
--     from the JWT (get_my_billing_status pattern, 0088), deliberately NOT via
--     auth_tenant_id(): that fn NULLs out suspended/paused tenants (0056), which
--     would flip this signal back to false on a billing lapse and break the
--     one-way contract. Navigation shape must stay predictable while paused —
--     actual data access is already gated by the 0056 chokepoint + 9.6 lockout.
--
-- File-based migration; never MCP apply. Roll-forward only.

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- One-way marker
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS inventory_first_used_at timestamptz;

COMMENT ON COLUMN public.tenants.inventory_first_used_at IS
  'Progressive disclosure — stamped once when the tenant''s first project is created; NEVER cleared (one-way door, ux-progressive-disclosure.md §1). Non-null = unfold Inventory surfaces.';

-- Backfill: any tenant that already has (or ever provisioned) a project.
UPDATE public.tenants t
   SET inventory_first_used_at = p.first_project_at
  FROM (
    SELECT tenant_id, min(created_at) AS first_project_at
      FROM public.projects
     GROUP BY tenant_id
  ) p
 WHERE p.tenant_id = t.id
   AND t.inventory_first_used_at IS NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- Flip ON at first project creation (any path: admin UI, mobile, ops, seed)
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._mark_tenant_uses_inventory()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  UPDATE public.tenants
     SET inventory_first_used_at = now()
   WHERE id = NEW.tenant_id
     AND inventory_first_used_at IS NULL;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._mark_tenant_uses_inventory() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS projects_mark_inventory_used ON public.projects;
CREATE TRIGGER projects_mark_inventory_used
  AFTER INSERT ON public.projects
  FOR EACH ROW EXECUTE FUNCTION public._mark_tenant_uses_inventory();

COMMENT ON FUNCTION public._mark_tenant_uses_inventory() IS
  'Progressive disclosure — stamps tenants.inventory_first_used_at on the tenant''s first project insert (idempotent; only fills NULL). SECURITY DEFINER because project creators have no tenants UPDATE grant.';

-- ────────────────────────────────────────────────────────────────────────────
-- The one canonical read (§1 "computed once, read everywhere")
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.tenant_uses_inventory()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (SELECT t.inventory_first_used_at IS NOT NULL
       FROM public.tenants t
      WHERE t.id = (
        CASE
          WHEN (auth.jwt() -> 'app_metadata') ->> 'tenant_id'
                 ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
          THEN ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid
          ELSE NULL
        END
      )),
    false
  )
$$;

REVOKE EXECUTE ON FUNCTION public.tenant_uses_inventory() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.tenant_uses_inventory() TO authenticated, service_role;

COMMENT ON FUNCTION public.tenant_uses_inventory() IS
  'Progressive disclosure — true once the caller''s tenant has ever created a project (one-way marker, never reverts, INCLUDING across billing suspension). Drives the admin Inventory sidebar gate and the mobile Availability/Booking/Amendments You-tab gates. Fail-closed only for a missing/invalid JWT tenant claim → false.';

COMMIT;
