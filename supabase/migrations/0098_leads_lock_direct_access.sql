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
-- What actually NEEDED direct authenticated-role access before this
-- migration (verified by reading every caller):
--   * create-lead / update-lead edge fns (run as the user): SELECT on
--     id / assigned_to_user_id / customer_code filtered by phone_hash or id
--     — the duplicate-phone check + customer-code fetch.
--   * NOTHING writes leads directly: create/update go through the
--     create_lead_with_pii / update_lead_with_pii SECURITY DEFINER fns;
--     assign/share/status flows are definer RPCs; cron + celebration fns use
--     service_role. No client app touches public.leads (zero .from('leads')
--     in apps/admin, apps/ops, apps/mobile; no embeds; no Realtime channel).
--
-- Fix: revoke ALL direct DML, move the dupe check into a definer RPC
-- (check_phone_duplicate below), and narrow SELECT to (id, tenant_id,
-- customer_code). Direct reassign (.update), delete, forged insert, and
-- tenant-wide PII reads (name, name_search, remarks, budgets, …) all die
-- at the privilege layer. Keeping phone_hash UNREADABLE also neutralises
-- audit H4 in practice: the unsalted SHA-256 over the ~4e9 Indian mobile
-- keyspace is brute-forceable in hours, but only if the hashes can be
-- read — and the only remaining readers are definer fns/service role.
-- (A pepper would add nothing against DB compromise: the pgp phone key
-- sits in the same database's vault.)
--
-- RLS tenant-isolation policy from 0009 stays: SELECT remains scoped to the
-- caller's tenant.

BEGIN;

REVOKE SELECT, INSERT, UPDATE, DELETE ON public.leads FROM authenticated;
REVOKE ALL ON public.leads FROM anon;

GRANT SELECT (id, tenant_id, customer_code) ON public.leads TO authenticated;

-- ── check_phone_duplicate() — the dupe probe the edge fns now call ─────────
-- Replaces the edge fns' direct phone_hash SELECTs. Tenant-scoped, returns
-- only what the duplicate UX needs: whether a duplicate exists and the
-- owner's display name. Never returns the hash or any PII.
CREATE OR REPLACE FUNCTION public.check_phone_duplicate(
  p_phone_hash      text,
  p_exclude_lead_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant uuid := public.auth_tenant_id();
  v_row    RECORD;
  v_owner  text;
BEGIN
  IF auth.uid() IS NULL OR v_tenant IS NULL THEN
    RAISE EXCEPTION 'unauthorised' USING ERRCODE = '42501';
  END IF;

  SELECT l.id, l.assigned_to_user_id
    INTO v_row
    FROM public.leads l
   WHERE l.tenant_id = v_tenant
     AND l.phone_hash = p_phone_hash
     AND (p_exclude_lead_id IS NULL OR l.id <> p_exclude_lead_id)
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  IF v_row.assigned_to_user_id IS NOT NULL THEN
    SELECT u.email_or_username INTO v_owner
      FROM public.users u WHERE u.id = v_row.assigned_to_user_id;
  END IF;

  RETURN jsonb_build_object(
    'found',      true,
    'lead_id',    v_row.id,
    'owner_name', coalesce(v_owner, 'another employee')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.check_phone_duplicate(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_phone_duplicate(text, uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.check_phone_duplicate(text, uuid) IS
  '0098 (audit C2/H4) — tenant-scoped duplicate-phone probe for the create-lead/update-lead edge fns. Returns {found[,lead_id,owner_name]}; never exposes phone_hash or PII. Exists so authenticated needs NO SELECT privilege on leads.phone_hash.';

COMMENT ON TABLE public.leads IS
  'Story 2.1 — Core lead record. PII encrypted at column level (Edge Function); phone_hash enables duplicate detection without decryption. 0098: direct client access is SELECT-only on (id, tenant_id, customer_code); dupe checks go through check_phone_duplicate(); every other read and ALL writes go through SECURITY DEFINER RPCs / service-role fns.';

COMMIT;
