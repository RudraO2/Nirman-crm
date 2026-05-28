-- Story 2.4 — get_lead_by_id + update_lead_with_pii
-- FRs: FR-1 (14-field edit), FR-3 (duplicate phone on update), FR-19 (field_updated timeline)
-- Both SECURITY DEFINER: vault access for PII decrypt/re-encrypt.

-- ────────────────────────────────────────────────────────────────────────────
-- get_lead_by_id — single lead fetch with PII decrypted + project_ids array
-- Returns zero rows if lead not found or not owned by caller (no 403 leak).
-- ────────────────────────────────────────────────────────────────────────────
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
  project_ids        uuid[]
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
    )
  FROM public.leads l
  WHERE l.id = p_lead_id
    AND l.assigned_to_user_id = v_user_id;
END;
$$;

COMMENT ON FUNCTION public.get_lead_by_id(uuid) IS
  'Story 2.4 — Single lead fetch with PII decrypted + project_ids. Returns 0 rows if not found or not owned by caller (no 403 leak).';

REVOKE EXECUTE ON FUNCTION public.get_lead_by_id(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_lead_by_id(uuid) TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- update_lead_with_pii — full-replacement update with PII re-encryption
-- Verifies ownership (assigned_to_user_id = auth.uid()).
-- Logs field_updated timeline event.
-- project_ids managed by Edge Function (delete + re-insert in lead_projects).
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_lead_with_pii(
  p_lead_id          uuid,
  p_status           public.lead_status,
  p_source           public.lead_source,
  p_phone_raw        text,         -- normalized 10-digit
  p_phone_hash       text,         -- sha256 hex, computed by Edge Function
  p_name             text,         -- plaintext or NULL
  p_property_type    text,
  p_location         text,
  p_budget_min       bigint,
  p_budget_max       bigint,
  p_ticket_size      text,
  p_remarks          text,
  p_visit_date       timestamptz,
  p_next_followup_at timestamptz,
  p_interest_type    text,
  p_is_incomplete    boolean,
  p_changed_fields   text[]        -- field names that changed, for timeline payload
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_tenant_id   uuid;
  v_actor_id    uuid;
  v_pii_key     text;
  v_name_enc    bytea;
  v_phone_enc   bytea;
  v_name_search text;
  v_rows        int;
BEGIN
  v_tenant_id := public.auth_tenant_id();
  v_actor_id  := auth.uid();

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'missing_tenant_context' USING ERRCODE = 'P0001';
  END IF;

  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'missing_actor' USING ERRCODE = 'P0001';
  END IF;

  SELECT decrypted_secret INTO v_pii_key
  FROM vault.decrypted_secrets
  WHERE name = 'lead_pii_key'
  LIMIT 1;

  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing' USING ERRCODE = 'P0003';
  END IF;

  -- Re-encrypt PII
  v_phone_enc := extensions.pgp_sym_encrypt(p_phone_raw, v_pii_key);

  IF p_name IS NOT NULL AND length(trim(p_name)) > 0 THEN
    v_name_enc    := extensions.pgp_sym_encrypt(p_name, v_pii_key);
    v_name_search := lower(p_name);
  ELSE
    v_name_enc    := NULL;
    v_name_search := NULL;
  END IF;

  UPDATE public.leads SET
    status             = p_status,
    source             = p_source,
    phone_encrypted    = v_phone_enc,
    phone_hash         = p_phone_hash,
    name_encrypted     = v_name_enc,
    name_search        = v_name_search,
    property_type      = p_property_type,
    location           = p_location,
    budget_min         = p_budget_min,
    budget_max         = p_budget_max,
    ticket_size        = p_ticket_size,
    remarks            = p_remarks,
    visit_date         = p_visit_date,
    next_followup_at   = p_next_followup_at,
    interest_type      = p_interest_type,
    is_incomplete      = p_is_incomplete,
    last_action_at     = now()
  WHERE id              = p_lead_id
    AND assigned_to_user_id = v_actor_id
    AND tenant_id       = v_tenant_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RAISE EXCEPTION 'lead_not_found_or_forbidden'
      USING ERRCODE = 'P0002';
  END IF;

  IF array_length(p_changed_fields, 1) > 0 THEN
    PERFORM public.log_timeline_event(
      p_lead_id,
      'field_updated'::public.timeline_event_type,
      jsonb_build_object(
        'fields',        p_changed_fields,
        'is_incomplete', p_is_incomplete,
        'status',        p_status::text
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'is_incomplete', p_is_incomplete,
    'status',        p_status::text
  );
END;
$$;

COMMENT ON FUNCTION public.update_lead_with_pii(
  uuid, public.lead_status, public.lead_source,
  text, text, text, text, text, bigint, bigint,
  text, text, timestamptz, timestamptz, text, boolean, text[]
) IS
  'Story 2.4 — Full-replacement lead update with PII re-encryption via Vault + pgcrypto. '
  'Ownership-gated (assigned_to_user_id = auth.uid()). Logs field_updated to Timeline.';

REVOKE EXECUTE ON FUNCTION public.update_lead_with_pii(
  uuid, public.lead_status, public.lead_source,
  text, text, text, text, text, bigint, bigint,
  text, text, timestamptz, timestamptz, text, boolean, text[]
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lead_with_pii(
  uuid, public.lead_status, public.lead_source,
  text, text, text, text, text, bigint, bigint,
  text, text, timestamptz, timestamptz, text, boolean, text[]
) TO authenticated;
