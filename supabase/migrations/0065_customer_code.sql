-- 0065_customer_code.sql
-- Story 13.3 (Epic 13) — FR-44. System-generated customer code (free-channel delivery).
--
-- Generates a per-tenant-unique customer_code (NIR-XXXXX) inside create_lead_with_pii on insert,
-- and logs a code_generated Timeline event. Delivery is free: the create-lead edge fn returns the
-- code + a wa.me deep link the agent sends (SMS deferred — pluggable paid adapter).
--
-- Also adds the new lead-side timeline_event_type values used across Epic 13
-- (code_generated, visit_verified, visit_logged, lead_reclaimed) — bare ADD VALUEs before the
-- txn block (new labels committed before use; the fn only references them as literals).
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

ALTER TYPE public.timeline_event_type ADD VALUE IF NOT EXISTS 'code_generated';
ALTER TYPE public.timeline_event_type ADD VALUE IF NOT EXISTS 'visit_verified';
ALTER TYPE public.timeline_event_type ADD VALUE IF NOT EXISTS 'visit_logged';
ALTER TYPE public.timeline_event_type ADD VALUE IF NOT EXISTS 'lead_reclaimed';

BEGIN;

CREATE OR REPLACE FUNCTION public.create_lead_with_pii(
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
  p_secondary_phone_raw  text DEFAULT NULL,
  p_secondary_phone_hash text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_tenant_id    uuid;
  v_actor_id     uuid;
  v_pii_key      text;
  v_name_enc     bytea;
  v_phone_enc    bytea;
  v_sec_enc      bytea;
  v_name_search  text;
  v_lead_id      uuid;
  v_code         text;
  v_try          int := 0;
BEGIN
  v_tenant_id := public.auth_tenant_id();
  v_actor_id  := auth.uid();

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'missing_tenant_context: app_metadata.tenant_id not set in JWT' USING ERRCODE = 'P0001';
  END IF;
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'missing_actor: auth.uid() returned NULL' USING ERRCODE = 'P0001';
  END IF;

  SELECT decrypted_secret INTO v_pii_key
  FROM vault.decrypted_secrets WHERE name = 'lead_pii_key' LIMIT 1;
  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing: vault secret lead_pii_key not configured' USING ERRCODE = 'P0003';
  END IF;

  v_phone_enc := extensions.pgp_sym_encrypt(p_phone_raw, v_pii_key);

  IF p_secondary_phone_raw IS NOT NULL AND length(trim(p_secondary_phone_raw)) > 0 THEN
    v_sec_enc := extensions.pgp_sym_encrypt(p_secondary_phone_raw, v_pii_key);
  END IF;

  IF p_name IS NOT NULL AND length(trim(p_name)) > 0 THEN
    v_name_enc    := extensions.pgp_sym_encrypt(p_name, v_pii_key);
    v_name_search := lower(p_name);
  END IF;

  -- Story 13.3: per-tenant-unique customer code. Bounded pre-check loop; the partial unique
  -- index leads_tenant_customer_code_idx is the backstop against the rare TOCTOU collision.
  LOOP
    v_try := v_try + 1;
    v_code := 'NIR-' || upper(substr(encode(extensions.gen_random_bytes(4), 'hex'), 1, 5));
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.leads
       WHERE tenant_id = v_tenant_id AND customer_code = v_code
    );
    IF v_try >= 10 THEN
      RAISE EXCEPTION 'customer_code_generation_failed' USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  INSERT INTO public.leads (
    tenant_id,                 assigned_to_user_id,
    status,                    source,
    name_encrypted,            phone_encrypted,
    secondary_phone_encrypted, secondary_phone_hash,
    phone_hash,                name_search,
    customer_code,
    property_type,             location,
    budget_min,                budget_max,
    ticket_size,               remarks,
    visit_date,                next_followup_at,
    interest_type,             is_incomplete,
    last_action_at
  ) VALUES (
    v_tenant_id,               v_actor_id,
    p_status,                  p_source,
    v_name_enc,                v_phone_enc,
    v_sec_enc,                 p_secondary_phone_hash,
    p_phone_hash,              v_name_search,
    v_code,
    p_property_type,           p_location,
    p_budget_min,              p_budget_max,
    p_ticket_size,             p_remarks,
    p_visit_date,              p_next_followup_at,
    p_interest_type,           p_is_incomplete,
    now()
  )
  RETURNING id INTO v_lead_id;

  PERFORM public.log_timeline_event(
    v_lead_id, 'lead_created'::public.timeline_event_type,
    jsonb_build_object('is_incomplete', p_is_incomplete, 'status', p_status::text)
  );
  PERFORM public.log_timeline_event(
    v_lead_id, 'code_generated'::public.timeline_event_type,
    jsonb_build_object('customer_code', v_code)
  );

  RETURN v_lead_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_lead_with_pii(
  public.lead_status, public.lead_source, text, text, text, text, text,
  bigint, bigint, text, text, timestamptz, timestamptz, text, boolean, text, text
) TO authenticated;

COMMIT;
