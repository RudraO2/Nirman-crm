-- 0061_partner_receptionist_guards.sql
-- Story 12.6 (Epic 12) — FR-40/FR-41. Partner sandbox + receptionist gate-not-own.
--
-- Most of 12.6 is ALREADY satisfied structurally:
--   • Partner lead scope — visible_user_ids() (0060) returns a partner's own agency users, so
--     get_team_leads() is the partner's scoped view; partners can never reach internal leads.
--   • cost_paise/margin omission for externals — enforced in the unit read paths (Epic 14.3) by
--     simply not selecting cost_paise for non-builder_head callers.
--   • Receptionist edit/open denial — every lead mutation/read RPC is ownership-gated
--     (assigned_to_user_id = auth.uid()); a receptionist owns nothing → already denied.
--
-- This migration adds the ONE explicit defense-in-depth guard the AC calls for: receptionists
-- are denied get_my_leads outright (not merely returned an empty set), so a future mis-assignment
-- can never leak lead data to a gate-only role.
--
-- get_my_leads body is reproduced from its LATEST definition (0042 — owned UNION ALL shared, with
-- the is_shared column + lead_shares join + PII decrypt) with ONLY the receptionist guard added.
-- Same RETURNS TABLE shape as 0042 → CREATE OR REPLACE is safe (no return-type change); grants
-- preserved, REVOKE/GRANT re-issued to match 0042.
--
-- CAPABILITY MATRIX enforcement map (single source — guards land with their feature RPC):
--   confirm hold→sold  → builder_head/team_leader guard in confirm_booking (Story 15.4)
--   edit inventory     → builder_head guard in inventory RPCs (Story 14.1/14.2)
--   view margin/cost   → builder_head-only read path (Story 14.3)
--   broadcast update   → builder_head guard in post_developer_update (Story 14.4)
--   log amendment      → excludes partner_agency in log_amendment (Story 16.2)
--   export             → builder_head-only (existing 0053; leader export = DENY, decided)
--   register lead      → receptionist denied in create_lead_with_pii rework (Story 13.5)
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_my_leads(
  p_limit  int DEFAULT 100,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id                 uuid,
  status             text,
  name               text,
  phone              text,
  source             text,
  property_type      text,
  location           text,
  budget_min         bigint,
  budget_max         bigint,
  ticket_size        text,
  visit_date         timestamptz,
  next_followup_at   timestamptz,
  is_incomplete      boolean,
  pending_outcome_at timestamptz,
  last_action_at     timestamptz,
  created_at         timestamptz,
  urgency_score      int,
  is_shared          boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_pii_key text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Story 12.6: receptionist is a gate-only role (verifies visits, owns no leads).
  -- Deny outright — defense-in-depth beyond ownership gating.
  IF public.auth_role_tier() = 'receptionist' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT s.decrypted_secret INTO v_pii_key
  FROM vault.decrypted_secrets s
  WHERE s.name = 'lead_pii_key'
  LIMIT 1;

  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing';
  END IF;

  RETURN QUERY
  WITH all_leads AS (
    -- Owned leads (is_shared = false)
    SELECT
      l.id,
      l.status::text                                                        AS status,
      CASE WHEN l.name_encrypted IS NOT NULL
           THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
           ELSE NULL END                                                    AS name,
      extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key)             AS phone,
      l.source::text                                                        AS source,
      l.property_type,
      l.location,
      l.budget_min,
      l.budget_max,
      l.ticket_size,
      l.visit_date,
      l.next_followup_at,
      l.is_incomplete,
      l.pending_outcome_at,
      l.last_action_at,
      l.created_at,
      false                                                                 AS is_shared
    FROM public.leads l
    WHERE l.assigned_to_user_id = v_user_id
      AND l.status NOT IN ('dead', 'sold', 'future')

    UNION ALL

    -- Shared leads: recipient = caller, caller is not the owner
    SELECT
      l.id,
      l.status::text                                                        AS status,
      CASE WHEN l.name_encrypted IS NOT NULL
           THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
           ELSE NULL END                                                    AS name,
      extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key)             AS phone,
      l.source::text                                                        AS source,
      l.property_type,
      l.location,
      l.budget_min,
      l.budget_max,
      l.ticket_size,
      l.visit_date,
      l.next_followup_at,
      l.is_incomplete,
      l.pending_outcome_at,
      l.last_action_at,
      l.created_at,
      true                                                                  AS is_shared
    FROM public.leads l
    JOIN public.lead_shares ls
      ON ls.lead_id = l.id AND ls.recipient_user_id = v_user_id
    WHERE l.status NOT IN ('dead', 'sold', 'future')
      AND l.assigned_to_user_id <> v_user_id
  ),
  scored AS (
    SELECT
      a.id, a.status, a.name, a.phone, a.source, a.property_type, a.location,
      a.budget_min, a.budget_max, a.ticket_size, a.visit_date, a.next_followup_at,
      a.is_incomplete, a.pending_outcome_at, a.last_action_at, a.created_at, a.is_shared,
      CASE
        WHEN a.pending_outcome_at IS NOT NULL                                   THEN 1000
        WHEN a.status = 'hot'  AND a.next_followup_at IS NOT NULL
             AND a.next_followup_at < now()                                     THEN  700
        WHEN a.status = 'hot'  AND a.next_followup_at IS NOT NULL
             AND a.next_followup_at::date = current_date                        THEN  600
        WHEN a.status = 'hot'                                                   THEN  500
        WHEN a.status = 'warm' AND a.next_followup_at IS NOT NULL
             AND a.next_followup_at < now()                                     THEN  400
        WHEN a.status = 'warm'                                                  THEN  300
        WHEN a.status = 'cold' AND a.next_followup_at IS NOT NULL
             AND a.next_followup_at < now()                                     THEN  250
        WHEN a.status = 'cold'                                                  THEN  200
        WHEN a.last_action_at < now() - interval '7 days'                      THEN   50
        ELSE 100
      END::int                                                             AS urgency_score
    FROM all_leads a
  )
  SELECT
    s.id, s.status, s.name, s.phone, s.source, s.property_type, s.location,
    s.budget_min, s.budget_max, s.ticket_size, s.visit_date, s.next_followup_at,
    s.is_incomplete, s.pending_outcome_at, s.last_action_at, s.created_at,
    s.urgency_score, s.is_shared
  FROM scored s
  ORDER BY s.urgency_score DESC, s.last_action_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION public.get_my_leads(int, int) IS
  'Story 4.4 + 12.6 — urgency-sorted active leads for auth.uid(): owned (is_shared=false) UNION ALL shared (is_shared=true). Decrypts PII via vault. Excludes dead/sold/future. Receptionist tier denied outright.';

REVOKE EXECUTE ON FUNCTION public.get_my_leads(int, int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_leads(int, int) TO authenticated;

COMMIT;
