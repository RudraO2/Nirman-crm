-- 0105_active_holds_status_version.sql
-- Robustness-audit 2026-07-11 LOW: the admin holds page called
-- change_unit_inventory_state('force_release') with p_expected_version: null, skipping the
-- optimistic-concurrency check entirely. get_active_holds now also returns the unit's
-- status_version (the CAS token from 0070), captured at LOAD time, so clients can pass the
-- version of the row the operator was actually looking at — a hold that was confirmed/expired
-- since the page loaded then fails with unit_version_conflict instead of silently releasing.
--
-- Return-type change ⇒ DROP + CREATE (CREATE OR REPLACE cannot alter OUT columns).
-- Extra trailing column is additive for existing callers (admin holds page, mobile booking
-- dashboard parse rows by column name). Body otherwise identical to 0079.
-- File-based migration; never MCP apply.

BEGIN;

DROP FUNCTION IF EXISTS public.get_active_holds(uuid, uuid);

CREATE FUNCTION public.get_active_holds(
  p_project_id uuid DEFAULT NULL,
  p_agent_id   uuid DEFAULT NULL
)
RETURNS TABLE (
  hold_id             uuid,
  unit_id             uuid,
  unit_no             text,
  project_id          uuid,
  lead_id             uuid,
  lead_name           text,
  holding_agent_id    uuid,
  agent_name          text,
  held_at             timestamptz,
  expires_at          timestamptz,
  seconds_to_expiry   bigint,
  unit_status_version int
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
  v_tenant_id uuid;
  v_pii_key   text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  SELECT decrypted_secret INTO v_pii_key FROM vault.decrypted_secrets WHERE name = 'lead_pii_key' LIMIT 1;

  RETURN QUERY
  SELECT
    h.id, h.unit_id, u.unit_no, u.project_id, h.lead_id,
    CASE WHEN v_pii_key IS NOT NULL AND l.name_encrypted IS NOT NULL
         THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key) ELSE NULL END,
    h.holding_agent_id, ag.email_or_username,
    h.held_at, h.expires_at,
    GREATEST(0, EXTRACT(EPOCH FROM (h.expires_at - now()))::bigint),
    u.status_version
  FROM public.unit_holds h
  JOIN public.units u ON u.id = h.unit_id
  LEFT JOIN public.leads l ON l.id = h.lead_id
  LEFT JOIN public.users ag ON ag.id = h.holding_agent_id
  WHERE h.tenant_id = v_tenant_id
    AND h.released_at IS NULL
    AND h.holding_agent_id IN (SELECT v.user_id FROM public.visible_user_ids() v)
    AND (p_project_id IS NULL OR u.project_id = p_project_id)
    AND (p_agent_id   IS NULL OR h.holding_agent_id = p_agent_id)
  ORDER BY h.expires_at ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_active_holds(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_active_holds(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.get_active_holds(uuid, uuid) IS
  'Story 15.5 + audit-0105 — active holds (released_at IS NULL) scoped to visible_user_ids(); unit/lead/agent + seconds_to_expiry + unit_status_version (CAS token for force_release). Lead name decrypted via vault. Filter by project/agent.';

COMMIT;
