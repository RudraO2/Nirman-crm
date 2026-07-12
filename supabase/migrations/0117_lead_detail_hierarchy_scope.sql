-- 0117_lead_detail_hierarchy_scope.sql
-- Bug found live on-device 2026-07-12: tapping a lead in "Team leads" toasts
-- "Lead not found in your queue" for any lead the caller doesn't OWN.
--
-- Root cause: get_team_leads (0060, Epic 12) lists leads across the caller's
-- visible_user_ids() tree — leader=subtree, head=all internal, partner=agency —
-- but get_lead_by_id (Story 4.4, last touched 0093) still gates on the
-- pre-hierarchy rule "owned OR explicitly shared". List scope ≠ detail scope:
-- every team-list row for someone else's lead was un-openable.
--
-- Fix: add the same visible_user_ids() set as a third access branch. No new
-- exposure — get_team_leads already returns these leads' decrypted name/phone
-- to the same callers; the detail view now simply agrees with the list.
-- Rep/receptionist: visible_user_ids()=self, so nothing changes for them.
-- Fail-closed: visible_user_ids() returns empty on missing/suspended context.
--
-- Body reproduced verbatim from 0093; ONLY the WHERE clause gains the branch.
-- File-based migration; never MCP apply.

BEGIN;

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
      -- 0117: hierarchy scope — same set get_team_leads lists (leader subtree,
      -- head all-internal, partner own-agency; self for everyone else)
      OR l.assigned_to_user_id IN (SELECT vu.user_id FROM public.visible_user_ids() vu)
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_lead_by_id(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_lead_by_id(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_lead_by_id(uuid) IS
  'Story 4.4 + 13.8 + 0117 — Single lead fetch. Access: owned, explicitly shared, OR within the caller''s visible_user_ids() hierarchy (matches get_team_leads scope). is_shared = "not assigned to caller". Returns customer_code + visit_count.';

COMMIT;
