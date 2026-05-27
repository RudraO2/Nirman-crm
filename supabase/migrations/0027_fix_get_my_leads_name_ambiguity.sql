-- Fix: column "name" ambiguous in get_my_leads — collides with vault.decrypted_secrets.name
-- Roll-forward only. Never edit after apply.

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
  urgency_score      int
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
    WHERE l.assigned_to_user_id = v_user_id
      AND l.status NOT IN ('dead', 'sold', 'future')
  )
  SELECT
    s.id,
    s.status,
    s.name,
    s.phone,
    s.source,
    s.property_type,
    s.location,
    s.budget_min,
    s.budget_max,
    s.ticket_size,
    s.visit_date,
    s.next_followup_at,
    s.is_incomplete,
    s.pending_outcome_at,
    s.last_action_at,
    s.created_at,
    s.urgency_score
  FROM scored s
  ORDER BY s.urgency_score DESC, s.last_action_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_leads(int, int) TO authenticated;
