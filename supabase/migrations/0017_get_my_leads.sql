-- Story 2.5 — get_my_leads: urgency-sorted active leads for current user with PII decrypted
-- SECURITY DEFINER: accesses vault.decrypted_secrets to decrypt name + phone
-- auth.uid() is session-level and preserved through SECURITY DEFINER context
-- Urgency tiers: pending_outcome(1000) > hot+overdue(700) > hot+today(600) > hot(500)
--                > warm+overdue(400) > warm(300) > cold+overdue(250) > cold(200) > stale(50)

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

  SELECT decrypted_secret INTO v_pii_key
  FROM vault.decrypted_secrets
  WHERE name = 'lead_pii_key'
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

COMMENT ON FUNCTION public.get_my_leads(int, int) IS
  'Story 2.5 — Returns urgency-sorted active leads for auth.uid(). Decrypts PII via vault lead_pii_key. Excludes dead/sold/future.';

GRANT EXECUTE ON FUNCTION public.get_my_leads(int, int) TO authenticated;
