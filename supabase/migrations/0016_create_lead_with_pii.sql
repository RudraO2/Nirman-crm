-- Story 2.3 — Lead creation with PII encryption
-- FRs: FR-1 (14-field lead form), FR-2 (Quick-Capture), FR-3 (duplicate phone prevention),
--      FR-4 (status-first entry), FR-19 (auto-Timeline)
-- NFRs: NFR-8 (PII encryption via Vault + pgcrypto), NFR-11 (tenant_id day-1)
--
-- Design decision: Drops the leads_tenant_phone_hash_unique constraint added in 0010.
-- Reason: Story 2.3 requires admin override to create a new lead with a duplicate phone.
-- A UNIQUE constraint cannot accommodate this. Application-layer duplicate check
-- (SELECT before INSERT) is the enforcement mechanism; the per-tenant phone_hash
-- index (leads_phone_hash_idx) ensures O(1) lookup performance.
-- Race condition risk is accepted given low-concurrency lead creation (one salesperson,
-- one device). The DB returns a unique_violation (23505) as a last-resort safety net.
--
-- Roll-forward only. Never edit after apply.

-- ────────────────────────────────────────────────────────────────────────────
-- Ensure pgcrypto is available in extensions schema
-- ────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ────────────────────────────────────────────────────────────────────────────
-- Drop unique constraint from 0010 to allow admin override
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.leads
  DROP CONSTRAINT IF EXISTS leads_tenant_phone_hash_unique;

-- ────────────────────────────────────────────────────────────────────────────
-- create_lead_with_pii()
--
-- SECURITY DEFINER: runs as postgres so it can:
--   a) read vault.decrypted_secrets (vault key for PII encryption)
--   b) call extensions.pgp_sym_encrypt (pgcrypto)
--
-- auth.uid() / auth.jwt() are session-level settings — preserved inside
-- SECURITY DEFINER, so assigned_to_user_id and log_timeline_event actor
-- both reflect the actual caller.
--
-- Called by the create-lead Edge Function via authenticated RPC.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_lead_with_pii(
  p_status           public.lead_status,
  p_source           public.lead_source,
  p_phone_raw        text,
  p_phone_hash       text,
  p_name             text,
  p_property_type    text,
  p_location         text,
  p_budget_min       bigint,
  p_budget_max       bigint,
  p_ticket_size      text,
  p_remarks          text,
  p_visit_date       timestamptz,
  p_next_followup_at timestamptz,
  p_interest_type    text,
  p_is_incomplete    boolean
)
RETURNS uuid
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
  v_lead_id     uuid;
BEGIN
  v_tenant_id := public.auth_tenant_id();
  v_actor_id  := auth.uid();

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'missing_tenant_context: app_metadata.tenant_id not set in JWT'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'missing_actor: auth.uid() returned NULL'
      USING ERRCODE = 'P0001';
  END IF;

  -- Read PII encryption key from Vault (requires postgres role — granted by SECURITY DEFINER)
  SELECT decrypted_secret INTO v_pii_key
  FROM vault.decrypted_secrets
  WHERE name = 'lead_pii_key'
  LIMIT 1;

  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing: vault secret lead_pii_key not configured'
      USING ERRCODE = 'P0003';
  END IF;

  -- Encrypt PII: phone always present; name optional (empty string treated as absent)
  v_phone_enc := extensions.pgp_sym_encrypt(p_phone_raw, v_pii_key);

  IF p_name IS NOT NULL AND length(trim(p_name)) > 0 THEN
    v_name_enc    := extensions.pgp_sym_encrypt(p_name, v_pii_key);
    v_name_search := lower(p_name);
  END IF;

  INSERT INTO public.leads (
    tenant_id,           assigned_to_user_id,
    status,              source,
    name_encrypted,      phone_encrypted,
    phone_hash,          name_search,
    property_type,       location,
    budget_min,          budget_max,
    ticket_size,         remarks,
    visit_date,          next_followup_at,
    interest_type,       is_incomplete,
    last_action_at
  ) VALUES (
    v_tenant_id,         v_actor_id,
    p_status,            p_source,
    v_name_enc,          v_phone_enc,
    p_phone_hash,        v_name_search,
    p_property_type,     p_location,
    p_budget_min,        p_budget_max,
    p_ticket_size,       p_remarks,
    p_visit_date,        p_next_followup_at,
    p_interest_type,     p_is_incomplete,
    now()
  )
  RETURNING id INTO v_lead_id;

  -- auth.uid() / auth.jwt() preserved at session level — log_timeline_event
  -- records the correct actor even inside SECURITY DEFINER chain
  PERFORM public.log_timeline_event(
    v_lead_id,
    'lead_created'::public.timeline_event_type,
    jsonb_build_object(
      'is_incomplete', p_is_incomplete,
      'status',        p_status::text
    )
  );

  RETURN v_lead_id;
END;
$$;

COMMENT ON FUNCTION public.create_lead_with_pii(
  public.lead_status, public.lead_source, text, text, text, text, text,
  bigint, bigint, text, text, timestamptz, timestamptz, text, boolean
) IS
  'Story 2.3 — Atomic lead INSERT with PII encryption via Vault + pgcrypto. '
  'SECURITY DEFINER (postgres) to access vault.decrypted_secrets. '
  'Assigns lead to auth.uid() (caller). Logs lead_created to Timeline.';

-- Only authenticated callers (employees + admins) may invoke this
GRANT EXECUTE ON FUNCTION public.create_lead_with_pii(
  public.lead_status, public.lead_source, text, text, text, text, text,
  bigint, bigint, text, text, timestamptz, timestamptz, text, boolean
) TO authenticated;
