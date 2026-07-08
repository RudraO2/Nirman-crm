-- 0060_visibility.sql
-- Story 12.5 (Epic 12) — FR-40. Hierarchical lead visibility.
--
-- visible_user_ids(): the ONE new visibility primitive. Self for reps; recursive subtree for
-- leaders; whole internal tree for heads; agency-only for partners. Consumed by get_team_leads
-- and (later) the booking dashboard (15.5).
--
-- get_team_leads(): a faithful clone of get_my_leads (latest def 0027) scoped to
-- assigned_to_user_id IN (visible_user_ids()) instead of = auth.uid(), with the owner id added
-- to the output so a leader can see who holds each lead. get_my_leads itself is UNCHANGED —
-- reps keep exact existing behaviour (FR-18 preserved).
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

-- ── visible_user_ids() — caller's visibility set ────────────────────────────
CREATE OR REPLACE FUNCTION public.visible_user_ids()
RETURNS TABLE(user_id uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_tier   text := public.auth_role_tier();
  v_tenant uuid := public.auth_tenant_id();
  v_agency uuid;
BEGIN
  IF v_uid IS NULL OR v_tenant IS NULL THEN
    RETURN;  -- no context → empty set (fail-closed)
  END IF;

  IF v_tier IN ('builder_head', 'super_admin') THEN
    RETURN QUERY
      SELECT u.id FROM public.users u
       WHERE u.tenant_id = v_tenant AND u.is_external = false;
  ELSIF v_tier = 'partner_agency' THEN
    SELECT u.agency_id INTO v_agency FROM public.users u WHERE u.id = v_uid;
    RETURN QUERY
      SELECT u.id FROM public.users u
       WHERE u.tenant_id = v_tenant AND u.agency_id = v_agency;  -- NULL agency ⇒ empty
  ELSIF v_tier = 'team_leader' THEN
    RETURN QUERY
      WITH RECURSIVE subtree AS (
        SELECT u.id, u.reports_to_user_id
          FROM public.users u
         WHERE u.id = v_uid
        UNION ALL
        SELECT c.id, c.reports_to_user_id
          FROM public.users c
          JOIN subtree s ON c.reports_to_user_id = s.id
      )
      SELECT s.id FROM subtree s;
  ELSE
    -- front_line_rep / receptionist: only themselves (receptionist owns nothing anyway).
    RETURN QUERY SELECT v_uid;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.visible_user_ids() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.visible_user_ids() TO authenticated, service_role;

COMMENT ON FUNCTION public.visible_user_ids() IS
  'Story 12.5 — set of user_ids the caller may see. Rep=self; team_leader=reporting subtree; builder_head/super_admin=whole internal tree; partner_agency=own agency. Fail-closed on missing context.';

-- ── get_team_leads() — get_my_leads cloned, subtree-scoped ──────────────────
CREATE OR REPLACE FUNCTION public.get_team_leads(
  p_limit  int DEFAULT 100,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id                  uuid,
  assigned_to_user_id uuid,
  status              text,
  name                text,
  phone               text,
  source              text,
  property_type       text,
  location            text,
  budget_min          bigint,
  budget_max          bigint,
  ticket_size         text,
  visit_date          timestamptz,
  next_followup_at    timestamptz,
  is_incomplete       boolean,
  pending_outcome_at  timestamptz,
  last_action_at      timestamptz,
  created_at          timestamptz,
  urgency_score       int
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
  WITH scored AS (
    SELECT
      l.id,
      l.assigned_to_user_id,
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
      CASE
        WHEN l.pending_outcome_at IS NOT NULL                                   THEN 1000
        WHEN l.status = 'hot'  AND l.next_followup_at IS NOT NULL
             AND l.next_followup_at < now()                                     THEN  700
        WHEN l.status = 'hot'  AND l.next_followup_at IS NOT NULL
             AND l.next_followup_at::date = current_date                        THEN  600
        WHEN l.status = 'hot'                                                   THEN  500
        WHEN l.status = 'warm' AND l.next_followup_at IS NOT NULL
             AND l.next_followup_at < now()                                     THEN  400
        WHEN l.status = 'warm'                                                  THEN  300
        WHEN l.status = 'cold' AND l.next_followup_at IS NOT NULL
             AND l.next_followup_at < now()                                     THEN  250
        WHEN l.status = 'cold'                                                  THEN  200
        WHEN l.last_action_at < now() - interval '7 days'                      THEN   50
        ELSE 100
      END::int                                                             AS urgency_score
    FROM public.leads l
    WHERE l.assigned_to_user_id IN (SELECT v.user_id FROM public.visible_user_ids() v)
      AND l.status NOT IN ('dead', 'sold', 'future')
  )
  SELECT
    s.id, s.assigned_to_user_id, s.status, s.name, s.phone, s.source,
    s.property_type, s.location, s.budget_min, s.budget_max, s.ticket_size,
    s.visit_date, s.next_followup_at, s.is_incomplete, s.pending_outcome_at,
    s.last_action_at, s.created_at, s.urgency_score
  FROM scored s
  ORDER BY s.urgency_score DESC, s.last_action_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_team_leads(int, int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_team_leads(int, int) TO authenticated;

COMMENT ON FUNCTION public.get_team_leads(int, int) IS
  'Story 12.5 — leads for the caller''s visibility subtree (visible_user_ids()), urgency-sorted, PII-decrypted. Clone of get_my_leads with owner id surfaced. Reps see only their own (visible set = self); get_my_leads is unchanged.';

COMMIT;
