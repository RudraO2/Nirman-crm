-- 0099_inventory_lock_direct_access.sql
-- Robustness audit 2026-07-11, findings C3 + C4 (CRITICAL), H2, H3 (HIGH).
--
-- 0070/0075/0080 granted full SELECT/INSERT/UPDATE/DELETE to `authenticated`
-- on units, unit_holds and amendments, RLS-scoped only by tenant. Every
-- lifecycle guard (hold_unit's receptionist denial / ownership / verified
-- visit, confirm_booking's payment attestation + CAS, log_amendment /
-- set_amendment_status transitions) lives in SECURITY DEFINER RPCs — so a
-- plain REST PATCH could sell a unit with no hold, delete a rival's active
-- hold, resurrect an expired one, or skip the amendment lifecycle.
--
-- Verified direct authenticated-role usage before this migration:
--   * units: NO client reads or writes (all via get_project_units /
--     hold_unit / confirm_booking / admin RPCs). The mobile availability
--     grid subscribes to Realtime postgres_changes on units — WALRUS
--     authorizes via RLS + per-column SELECT privilege, and the app uses
--     events purely as an invalidation trigger (never renders the payload).
--   * unit_holds: ONE read — mobile getActiveHold() selects id, unit_id,
--     lead_id, holding_agent_id, expires_at filtered by unit_id +
--     released_at IS NULL (live countdown on a held unit). No writes.
--   * amendments: nothing. Mobile uses log_amendment/set_amendment_status
--     RPCs; the notification edge fn is service_role.
--
-- Fix:
--   * units — revoke ALL DML; SELECT re-granted on every column EXCEPT
--     cost_paise (H3: margin data was readable by any tenant member incl.
--     partner_agency; builder_head margin reads go through the
--     get_project_units definer RPC, unaffected). Realtime keeps working:
--     subscription filter column (project_id) stays selectable and WALRUS
--     omits non-privileged columns from payloads.
--   * unit_holds — revoke ALL DML, keep full SELECT (tenant-wide hold
--     visibility is by design — any agent sees a held unit's countdown).
--     Forge/hijack/resurrect all die at the privilege layer.
--   * amendments — revoke everything; RPC/service-role access only.
--
-- Tenant-isolation RLS policies from 0070/0075/0080 stay as-is.

BEGIN;

-- units (C3 + H3) ------------------------------------------------------------
REVOKE SELECT, INSERT, UPDATE, DELETE ON public.units FROM authenticated;
REVOKE ALL ON public.units FROM anon;

GRANT SELECT (id, tenant_id, project_id, tower_id, unit_no, floor,
              configuration, carpet_area_sqft, status, list_price_paise,
              status_version, created_at, updated_at)
  ON public.units TO authenticated;

COMMENT ON TABLE public.units IS
  'Story 14.1 — sellable units. status lifecycle documented in 0070 header. cost_paise is margin (builder_head-only, NOT column-granted to authenticated — 0099). status_version = CAS token for holds (15.2). 0099: direct client access is SELECT-only (minus cost_paise); all writes via SECURITY DEFINER RPCs.';

-- unit_holds (C4) ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON public.unit_holds FROM authenticated;
REVOKE ALL ON public.unit_holds FROM anon;

COMMENT ON TABLE public.unit_holds IS
  'Story 15.1 — unit holds. ACTIVE ⇔ released_at IS NULL (single source for 15.2 CAS + 15.3 cron). Partial-unique (unit_id) WHERE released_at IS NULL = at most one active hold per unit. 0099: SELECT-only for clients; INSERT/UPDATE/DELETE via hold_unit/confirm_booking/sweep RPCs only.';

-- amendments (H2) ------------------------------------------------------------
REVOKE SELECT, INSERT, UPDATE, DELETE ON public.amendments FROM authenticated;
REVOKE ALL ON public.amendments FROM anon;

COMMENT ON TABLE public.amendments IS
  'Story 16.1 — amendment requests. 0099: NO direct client access — reads and lifecycle writes go through the amendment SECURITY DEFINER RPCs; notifications via service-role edge fn.';

COMMIT;
