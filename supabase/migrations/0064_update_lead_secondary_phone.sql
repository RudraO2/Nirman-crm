-- 0064_update_lead_secondary_phone.sql
-- Story 13.2 (edit path) — FR-42. Symmetric secondary-phone handling on lead edit so an
-- Incomplete lead can be completed by adding a secondary phone.
--
-- Extends update_lead_with_pii with two params (secondary phone raw + hash). Signature changes
-- (17 → 19 args) → DROP + CREATE (roll-forward), re-issuing REVOKE/GRANT. Body otherwise the
-- 0019 definition verbatim; only the secondary-phone re-encrypt + UPDATE columns added.
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

DROP FUNCTION IF EXISTS public.update_lead_with_pii(
  uuid, public.lead_status, public.lead_source,
  text, text, text, text, text, bigint, bigint,
  text, text, timestamptz, timestamptz, text, boolean, text[]
);

CREATE OR REPLACE FUNCTION public.update_lead_with_pii(
  p_lead_id              uuid,
  p_status               public.lead_status,
  p_source               public.lead_source,
  p_phone_raw            text,
  p_phone_hash           text,
  p_name                 text,
  p_property_type        text,
  p_location             text,
  p_budget_min           bigint,
  p_budget_max           bigint,
  p_ticket_size          text,
  p_remarks              text,
  p_visit_date           timestamptz,
  p_next_followup_at     timestamptz,
  p_interest_type        text,
  p_is_incomplete        boolean,
  p_changed_fields       text[],
  p_secondary_phone_raw  text DEFAULT NULL,
  p_secondary_phone_hash text DEFAULT NULL
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
  v_sec_enc     bytea;
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

  v_phone_enc := extensions.pgp_sym_encrypt(p_phone_raw, v_pii_key);

  IF p_secondary_phone_raw IS NOT NULL AND length(trim(p_secondary_phone_raw)) > 0 THEN
    v_sec_enc := extensions.pgp_sym_encrypt(p_secondary_phone_raw, v_pii_key);
  ELSE
    v_sec_enc := NULL;
  END IF;

  IF p_name IS NOT NULL AND length(trim(p_name)) > 0 THEN
    v_name_enc    := extensions.pgp_sym_encrypt(p_name, v_pii_key);
    v_name_search := lower(p_name);
  ELSE
    v_name_enc    := NULL;
    v_name_search := NULL;
  END IF;

  UPDATE public.leads SET
    status                    = p_status,
    source                    = p_source,
    phone_encrypted           = v_phone_enc,
    phone_hash                = p_phone_hash,
    secondary_phone_encrypted = v_sec_enc,
    secondary_phone_hash      = p_secondary_phone_hash,
    name_encrypted            = v_name_enc,
    name_search               = v_name_search,
    property_type             = p_property_type,
    location                  = p_location,
    budget_min                = p_budget_min,
    budget_max                = p_budget_max,
    ticket_size               = p_ticket_size,
    remarks                   = p_remarks,
    visit_date                = p_visit_date,
    next_followup_at          = p_next_followup_at,
    interest_type             = p_interest_type,
    is_incomplete             = p_is_incomplete,
    last_action_at            = now()
  WHERE id                  = p_lead_id
    AND assigned_to_user_id = v_actor_id
    AND tenant_id           = v_tenant_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'lead_not_found_or_forbidden' USING ERRCODE = 'P0002';
  END IF;

  IF array_length(p_changed_fields, 1) > 0 THEN
    PERFORM public.log_timeline_event(
      p_lead_id,
      'field_updated'::public.timeline_event_type,
      jsonb_build_object('fields', p_changed_fields, 'is_incomplete', p_is_incomplete, 'status', p_status::text)
    );
  END IF;

  RETURN jsonb_build_object('is_incomplete', p_is_incomplete, 'status', p_status::text);
END;
$$;

COMMENT ON FUNCTION public.update_lead_with_pii(
  uuid, public.lead_status, public.lead_source, text, text, text, text, text,
  bigint, bigint, text, text, timestamptz, timestamptz, text, boolean, text[], text, text
) IS
  'Story 2.4 + 13.2 — full-replacement lead update with PII re-encryption (primary + secondary phone). Ownership-gated. Logs field_updated.';

REVOKE EXECUTE ON FUNCTION public.update_lead_with_pii(
  uuid, public.lead_status, public.lead_source, text, text, text, text, text,
  bigint, bigint, text, text, timestamptz, timestamptz, text, boolean, text[], text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lead_with_pii(
  uuid, public.lead_status, public.lead_source, text, text, text, text, text,
  bigint, bigint, text, text, timestamptz, timestamptz, text, boolean, text[], text, text
) TO authenticated;

COMMIT;
