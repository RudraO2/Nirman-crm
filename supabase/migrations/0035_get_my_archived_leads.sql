-- Story 2.8 — get_my_archived_leads: caller's archived leads (dead/sold/future) with PII decrypted.
-- Mirrors get_my_leads (0017) shape so the existing LeadListItem model parses both.
-- Adds archived_at (newest status_changed → dead/sold/future event) and optional search.
--
-- Search semantics:
--   - name substring (decrypted, ILIKE)
--   - exact phone after normalize_phone() input — matched via phone_hash (sha256 hex)
--   - combine with OR; trim + length > 0 required
--
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.get_my_archived_leads(
  p_q      text  DEFAULT NULL,
  p_limit  int   DEFAULT 50,
  p_offset int   DEFAULT 0
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
  archived_at        timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
  v_user_id  uuid := auth.uid();
  v_pii_key  text;
  v_q        text;
  v_phone    text;
  v_phone_hash text;
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

  -- Search inputs: normalize once.
  v_q := NULLIF(trim(COALESCE(p_q, '')), '');
  IF v_q IS NOT NULL THEN
    v_phone := public.normalize_phone(v_q);
    IF v_phone IS NOT NULL THEN
      v_phone_hash := encode(extensions.digest(v_phone, 'sha256'), 'hex');
    END IF;
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT
      l.id,
      l.status::text                                                   AS status,
      CASE WHEN l.name_encrypted IS NOT NULL
           THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
           ELSE NULL END                                               AS name,
      extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key)        AS phone,
      l.source::text                                                   AS source,
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
      l.phone_hash,
      (SELECT max(t.occurred_at)
         FROM public.lead_timeline t
        WHERE t.lead_id = l.id
          AND t.event_type = 'status_changed'
          AND t.payload->>'to' IN ('dead','sold','future'))            AS archived_at
    FROM public.leads l
    WHERE l.assigned_to_user_id = v_user_id
      AND l.status IN ('dead','sold','future')
  )
  SELECT
    b.id, b.status, b.name, b.phone, b.source, b.property_type, b.location,
    b.budget_min, b.budget_max, b.ticket_size, b.visit_date, b.next_followup_at,
    b.is_incomplete, b.pending_outcome_at, b.last_action_at, b.created_at,
    0::int AS urgency_score,   -- not meaningful for archived; mobile ignores
    b.archived_at
  FROM base b
  WHERE v_q IS NULL
     OR (b.name IS NOT NULL AND b.name ILIKE '%' || v_q || '%')
     OR (v_phone_hash IS NOT NULL AND b.phone_hash = v_phone_hash)
  ORDER BY b.archived_at DESC NULLS LAST, b.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION public.get_my_archived_leads(text, int, int) IS
  'Story 2.8 — Caller-scoped archived leads (dead/sold/future) with PII decrypted, optional name-substring OR exact-phone search. Newest archived first.';

REVOKE EXECUTE ON FUNCTION public.get_my_archived_leads(text, int, int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_archived_leads(text, int, int) TO authenticated;
