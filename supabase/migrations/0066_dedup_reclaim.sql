-- 0066_dedup_reclaim.sql
-- Story 13.5 (Epic 13) — FR-47. 90-day agent-lock dedup with reclaim-in-place.
--
-- Replaces the permanent app-layer block with: on register, SELECT the existing phone-row
-- FOR UPDATE; if locked (within 90 days AND owner active in last 30 days) → raise duplicate_lead;
-- else reclaim the SAME row (reassign to caller, reset lock, status warm) — one row per phone,
-- no new duplicate. Admin force-reclaim via p_force_reclaim (honoured only for role=admin).
--
-- NOTE (arch §15/§15.1): the 0010 unique constraint was already dropped by 0016 and is NOT
-- re-added (legacy admin-override duplicates would make ADD CONSTRAINT fail). Atomicity comes
-- from SELECT … FOR UPDATE here. Backfill lock_started_at = now() so NO historic lead is
-- reclaimable on day one (the critical party-review fix — never created_at).
--
-- Signature gains p_force_reclaim (17 → 18 args) → DROP + CREATE, GRANT re-issued.
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

-- Backfill: every existing lead gets a fresh 90-day clock from go-live. NEVER created_at.
UPDATE public.leads SET lock_started_at = now() WHERE lock_started_at IS NULL;

DROP FUNCTION IF EXISTS public.create_lead_with_pii(
  public.lead_status, public.lead_source, text, text, text, text, text,
  bigint, bigint, text, text, timestamptz, timestamptz, text, boolean, text, text
);

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
  p_secondary_phone_hash text DEFAULT NULL,
  p_force_reclaim        boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_tenant_id    uuid;
  v_actor_id     uuid;
  v_is_admin     boolean;
  v_pii_key      text;
  v_name_enc     bytea;
  v_phone_enc    bytea;
  v_sec_enc      bytea;
  v_name_search  text;
  v_lead_id      uuid;
  v_code         text;
  v_try          int := 0;
  v_existing     RECORD;
  v_locked       boolean;
BEGIN
  v_tenant_id := public.auth_tenant_id();
  v_actor_id  := auth.uid();
  v_is_admin  := ((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin';

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'missing_tenant_context: app_metadata.tenant_id not set in JWT' USING ERRCODE = 'P0001';
  END IF;
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'missing_actor: auth.uid() returned NULL' USING ERRCODE = 'P0001';
  END IF;

  -- ── Dedup / reclaim — atomic via FOR UPDATE on the existing phone-row ──────
  SELECT id, assigned_to_user_id, lock_started_at, last_action_at, created_at
    INTO v_existing
    FROM public.leads
   WHERE tenant_id = v_tenant_id AND phone_hash = p_phone_hash
   ORDER BY created_at ASC
   LIMIT 1
   FOR UPDATE;

  IF FOUND THEN
    v_locked := (now() < COALESCE(v_existing.lock_started_at, v_existing.created_at) + interval '90 days')
                AND (v_existing.last_action_at > now() - interval '30 days');

    IF v_locked AND NOT (p_force_reclaim AND v_is_admin) THEN
      -- Owner + unlock date surfaced to the edge fn (friendly error) via DETAIL.
      RAISE EXCEPTION 'duplicate_lead'
        USING ERRCODE = 'P0001',
              DETAIL = jsonb_build_object(
                'existing_lead_id', v_existing.id,
                'owner_user_id',    v_existing.assigned_to_user_id,
                'unlock_at',        COALESCE(v_existing.lock_started_at, v_existing.created_at) + interval '90 days'
              )::text;
    END IF;

    -- Reclaim-in-place: reassign the same row to the caller, reset the lock.
    UPDATE public.leads
       SET assigned_to_user_id = v_actor_id,
           lock_started_at     = now(),
           status              = 'warm',
           last_action_at      = now(),
           updated_at          = now()
     WHERE id = v_existing.id;

    PERFORM public.log_timeline_event(
      v_existing.id, 'lead_reclaimed'::public.timeline_event_type,
      jsonb_build_object('from_user_id', v_existing.assigned_to_user_id, 'to_user_id', v_actor_id)
    );

    RETURN v_existing.id;
  END IF;

  -- ── New lead path ─────────────────────────────────────────────────────────
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

  LOOP
    v_try := v_try + 1;
    v_code := 'NIR-' || upper(substr(encode(extensions.gen_random_bytes(4), 'hex'), 1, 5));
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.leads WHERE tenant_id = v_tenant_id AND customer_code = v_code
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
    customer_code,             lock_started_at,
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
    v_code,                    now(),
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
  bigint, bigint, text, text, timestamptz, timestamptz, text, boolean, text, text, boolean
) TO authenticated;

COMMENT ON FUNCTION public.create_lead_with_pii(
  public.lead_status, public.lead_source, text, text, text, text, text,
  bigint, bigint, text, text, timestamptz, timestamptz, text, boolean, text, text, boolean
) IS
  'Story 2.3 + 13.2/13.3/13.5 — register a lead. Atomic FOR UPDATE dedup: locked phone (≤90d & owner active ≤30d) raises duplicate_lead (DETAIL has owner+unlock_at); else reclaim-in-place (reassign same row, log lead_reclaimed); else insert new with customer_code. p_force_reclaim honoured only for admins.';

COMMIT;
