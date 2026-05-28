-- Story 2.4 patch — get_lead_by_id fixes:
--   1. `name` column ambiguity vs vault.decrypted_secrets.name when search_path includes vault
--   2. Missing remarks column in RETURNS TABLE — detail screen rendered empty remarks
-- DROP required because RETURNS TABLE shape changed (added remarks).
-- Roll-forward only. Never edit after apply.

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
  remarks            text
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
    l.remarks
  FROM public.leads l
  WHERE l.id = p_lead_id
    AND l.assigned_to_user_id = v_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_lead_by_id(uuid) TO authenticated;
