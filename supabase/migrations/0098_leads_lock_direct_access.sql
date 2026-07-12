-- 0098_leads_lock_direct_access.sql
-- Robustness audit 2026-07-11, finding C2 (CRITICAL).
--
-- 0009 granted SELECT/INSERT/UPDATE/DELETE on public.leads to `authenticated`
-- with only a tenant-isolation RLS policy. Ownership + hierarchy scoping
-- (rep sees own, leader sees subtree) lives exclusively inside SECURITY
-- DEFINER RPCs (get_my_leads / assign_lead / …), so any employee could
-- read, reassign, or delete ANY lead in the tenant straight through the
-- REST API with their own JWT — bypassing status guards and audit logging.
--
-- What actually NEEDS direct authenticated-role access (verified by reading
-- every caller):
--   * create-lead edge fn (runs as the user): SELECT id / assigned_to_user_id
--     / customer_code filtered by phone_hash or id — dupe-check + code fetch.
--   * update-lead edge fn (runs as the user): SELECT id / assigned_to_user_id
--     filtered by phone_hash — dupe-check.
--   * NOTHING writes leads directly: create/update go through the
--     create_lead_with_pii / update_lead_with_pii SECURITY DEFINER fns;
--     assign/share/status flows are definer RPCs; cron + celebration fns use
--     service_role. No client app touches public.leads (zero .from('leads')
--     in apps/admin, apps/ops, apps/mobile; no embeds; no Realtime channel).
--
-- Fix: revoke ALL direct DML, and narrow SELECT to exactly the columns the
-- dupe-check path needs. Direct reassign (.update), delete, forged insert,
-- and tenant-wide PII reads (name, name_search, remarks, budgets, …) all
-- die at the privilege layer. phone_hash stays selectable (the dupe-check
-- WHERE clause requires it); its brute-forceability is audit finding H4
-- (unsalted hash) and is fixed server-side, not here.
--
-- RLS tenant-isolation policy from 0009 stays: SELECT remains scoped to the
-- caller's tenant.

BEGIN;

REVOKE SELECT, INSERT, UPDATE, DELETE ON public.leads FROM authenticated;
REVOKE ALL ON public.leads FROM anon;

GRANT SELECT (id, tenant_id, assigned_to_user_id, phone_hash, customer_code)
  ON public.leads TO authenticated;

COMMENT ON TABLE public.leads IS
  'Story 2.1 — Core lead record. PII encrypted at column level (Edge Function); phone_hash enables duplicate detection without decryption. 0098: direct client access is SELECT-only on (id, tenant_id, assigned_to_user_id, phone_hash, customer_code) for the edge-fn dupe check; every other read and ALL writes go through SECURITY DEFINER RPCs / service-role fns.';

COMMIT;
