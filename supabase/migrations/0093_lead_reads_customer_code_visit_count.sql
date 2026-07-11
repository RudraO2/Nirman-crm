-- 0093_lead_reads_customer_code_visit_count.sql
-- Story 13.8-mobile — surface the customer visit code + visit count on the lead
-- LIST card (not only lead detail). Until now the mobile lead-detail screen read
-- `leads.customer_code, visit_count` via a lightweight tenant-scoped DIRECT select
-- (13.4-mobile shim), because neither read RPC returned the two columns. Per-row
-- direct reads across the whole list card would be wasteful, so this migration adds
-- the two columns to BOTH lead read RPCs so the mobile app can parse them off the
-- RPC row and retire the shim.
--
-- Both functions are reproduced VERBATIM from their latest prod definition with the
-- ONLY change being the two appended columns (`customer_code text`, `visit_count int`)
-- in the RETURNS TABLE + SELECT. Nothing else changes:
--   * get_my_leads — from 0092 (Story 9.6). The 0092 tenant chokepoint guard
--     (auth_tenant_id() IS NULL -> missing_tenant_context P0001) and the 12.6
--     receptionist deny are preserved UNCHANGED. `leads.visit_count` is
--     `int NOT NULL DEFAULT 0`; `customer_code` is nullable text (0062 columns).
--   * get_lead_by_id — from 0044 (P4). Same body; only the two columns appended.
--
-- Both are SECURITY DEFINER, authenticated-only; GRANTs re-issued.
-- Prod head is 0092. This is 0093. File-based, `supabase db push --linked`. NEVER MCP apply.

BEGIN;

-- 1. get_my_leads — 0092 body verbatim + customer_code/visit_count appended. ------------------------
-- Appending to the RETURNS TABLE changes the OUT-param row type, which CREATE OR
-- REPLACE cannot do → drop first. No CASCADE: nothing should depend on this fn
-- (it is a client-called RPC, not referenced by any view/policy) — fail loud if so.
DROP FUNCTION IF EXISTS public.get_my_leads(int, int);
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
  is_shared          boolean,
  customer_code      text,
  visit_count        int
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

  -- Story 9.6: HARD tenant cutoff. A suspended/cancelled (or lapsed) tenant resolves
  -- to a NULL auth_tenant_id() (0056 chokepoint: status IN trial,active only), so deny
  -- data with the standard `missing_tenant_context` signal — the app routes to the
  -- recharge screen instead of showing an error, and no lead data is reachable.
  -- Active/trial tenants: auth_tenant_id() is non-null → this is a no-op.
  IF public.auth_tenant_id() IS NULL THEN
    RAISE EXCEPTION 'missing_tenant_context' USING ERRCODE = 'P0001';
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
      false                                                                 AS is_shared,
      l.customer_code,
      l.visit_count
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
      true                                                                  AS is_shared,
      l.customer_code,
      l.visit_count
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
      a.customer_code, a.visit_count,
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
    s.urgency_score, s.is_shared, s.customer_code, s.visit_count
  FROM scored s
  ORDER BY s.urgency_score DESC, s.last_action_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION public.get_my_leads(int, int) IS
  'Story 4.4 + 12.6 + 9.6 + 13.8 — urgency-sorted active leads for auth.uid(): owned UNION ALL shared. Decrypts PII via vault. Excludes dead/sold/future. Receptionist denied. Fail-closed on tenant status via auth_tenant_id() (suspended tenant -> missing_tenant_context, no data). Story 13.8: now also returns customer_code + visit_count for the lead list card.';

REVOKE EXECUTE ON FUNCTION public.get_my_leads(int, int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_leads(int, int) TO authenticated;

-- 2. get_lead_by_id — 0044 body verbatim + customer_code/visit_count appended. --------------------
DROP FUNCTION IF EXISTS public.get_lead_by_id(uuid);
CREATE OR REPLACE FUNCTION public.get_lead_by_id(p_lead_id uuid)
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
  project_ids        uuid[],
  remarks            text,
  is_shared          boolean,
  customer_code      text,
  visit_count        int
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

  SELECT s.decrypted_secret INTO v_pii_key
  FROM vault.decrypted_secrets s
  WHERE s.name = 'lead_pii_key'
  LIMIT 1;

  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing';
  END IF;

  RETURN QUERY
  SELECT
    l.id,
    l.status::text,
    CASE WHEN l.name_encrypted IS NOT NULL
         THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
         ELSE NULL END,
    extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key),
    l.source::text,
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
    CASE
      WHEN l.pending_outcome_at IS NOT NULL                                THEN 1000
      WHEN l.status = 'hot' AND l.next_followup_at IS NOT NULL
           AND l.next_followup_at < now()                                  THEN  700
      WHEN l.status = 'hot' AND l.next_followup_at IS NOT NULL
           AND l.next_followup_at::date = current_date                     THEN  600
      WHEN l.status = 'hot'                                                THEN  500
      WHEN l.status = 'warm' AND l.next_followup_at IS NOT NULL
           AND l.next_followup_at < now()                                  THEN  400
      WHEN l.status = 'warm'                                               THEN  300
      WHEN l.status = 'cold' AND l.next_followup_at IS NOT NULL
           AND l.next_followup_at < now()                                  THEN  250
      WHEN l.status = 'cold'                                               THEN  200
      WHEN l.last_action_at < now() - interval '7 days'                   THEN   50
      ELSE 100
    END::int,
    COALESCE(
      (SELECT array_agg(lp.project_id ORDER BY lp.project_id)
         FROM public.lead_projects lp
        WHERE lp.lead_id = l.id),
      '{}'::uuid[]
    ),
    l.remarks,
    -- P4: COALESCE so NULL assigned_to (unassigned lead) yields false not NULL
    COALESCE((l.assigned_to_user_id <> v_user_id), false),
    l.customer_code,
    l.visit_count
  FROM public.leads l
  WHERE l.id = p_lead_id
    AND (
      l.assigned_to_user_id = v_user_id
      OR EXISTS (
        SELECT 1 FROM public.lead_shares ls
         WHERE ls.lead_id = l.id AND ls.recipient_user_id = v_user_id
      )
    );
END;
$$;

COMMENT ON FUNCTION public.get_lead_by_id(uuid) IS
  'Story 4.4 (patched P4) + 13.8 — Single lead fetch. Returns owned OR shared leads. is_shared uses COALESCE to avoid NULL when assigned_to is NULL. Story 13.8: now also returns customer_code + visit_count.';

REVOKE EXECUTE ON FUNCTION public.get_lead_by_id(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_lead_by_id(uuid) TO authenticated;

COMMIT;
