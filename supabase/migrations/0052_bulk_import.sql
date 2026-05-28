-- Story 6.1 — Excel Bulk Import
-- FRs: FR-bulk-import (Epic 6.1)
-- 'imported' already in timeline_event_type enum (migration 0012)
--
-- Roll-forward only. Never edit after apply.

-- ────────────────────────────────────────────────────────────────────────────
-- 1. check_phone_hashes(p_hashes text[])
--    Returns which hashes from p_hashes already exist in leads for this tenant.
--    Used by client preview step to show cross-db duplicate count.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.check_phone_hashes(p_hashes text[])
RETURNS TABLE (phone_hash text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_role      text;
  v_tenant_id uuid;
BEGIN
  v_role := (auth.jwt() -> 'app_metadata') ->> 'role';
  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'admin_required: only admins may call check_phone_hashes'
      USING ERRCODE = 'P0001';
  END IF;

  v_tenant_id := public.auth_tenant_id();

  RETURN QUERY
    SELECT l.phone_hash
    FROM public.leads l
    WHERE l.tenant_id = v_tenant_id
      AND l.phone_hash = ANY(p_hashes);
END;
$$;

REVOKE ALL ON FUNCTION public.check_phone_hashes(text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_phone_hashes(text[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.check_phone_hashes(text[]) TO authenticated;

COMMENT ON FUNCTION public.check_phone_hashes(text[]) IS
  'Story 6.1 — Returns phone_hash values from p_hashes that already exist in leads for the calling tenant. Admin-only. Used to compute cross-db duplicate count during import preview.';

-- ────────────────────────────────────────────────────────────────────────────
-- 2. bulk_import_leads(p_rows jsonb, p_employee_ids uuid[])
--    Full bulk import: dedup, PII encryption, round-robin assignment, timeline.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.bulk_import_leads(
  p_rows         jsonb,
  p_employee_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_role              text;
  v_tenant_id         uuid;
  v_batch_id          uuid := extensions.gen_random_uuid();
  v_pii_key           text;
  v_seen_hashes       text[] := '{}';
  v_total_rows        integer;
  v_row               jsonb;
  v_i                 integer;
  v_normalized        text;
  v_hash              text;
  v_name              text;
  v_source_raw        text;
  v_phone_enc         bytea;
  v_name_enc          bytea;
  v_name_search       text;
  v_source            public.lead_source;
  v_budget_min        bigint;
  v_budget_max        bigint;
  v_budget_raw        text;
  v_is_incomplete     boolean;
  v_lead_id           uuid;
  v_project_id        uuid;
  v_employee_id       uuid;
  v_imported          integer := 0;
  v_duplicates_skipped integer := 0;
  v_errors            integer := 0;
BEGIN
  -- Admin guard
  v_role := (auth.jwt() -> 'app_metadata') ->> 'role';
  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'admin_required: only admins may call bulk_import_leads'
      USING ERRCODE = 'P0001';
  END IF;

  v_tenant_id := public.auth_tenant_id();

  -- Require at least one employee
  IF p_employee_ids IS NULL OR array_length(p_employee_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'employee_ids_required: at least one employee must be selected'
      USING ERRCODE = 'P0001';
  END IF;

  -- Read PII key from Vault (SECURITY DEFINER gives postgres-role access)
  SELECT decrypted_secret INTO v_pii_key
  FROM vault.decrypted_secrets
  WHERE name = 'lead_pii_key'
  LIMIT 1;

  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing: vault secret lead_pii_key not configured'
      USING ERRCODE = 'P0003';
  END IF;

  v_total_rows := jsonb_array_length(p_rows);

  FOR v_i IN 0..v_total_rows - 1
  LOOP
    v_row := p_rows->v_i;

    -- a. Normalize phone; reject row if NULL
    v_normalized := public.normalize_phone(v_row->>'phone_raw');
    IF v_normalized IS NULL THEN
      v_errors := v_errors + 1;
      CONTINUE;
    END IF;

    -- b. Compute SHA-256 hash
    v_hash := encode(extensions.digest(v_normalized, 'sha256'), 'hex');

    -- c. Intra-batch dedup
    IF v_hash = ANY(v_seen_hashes) THEN
      v_duplicates_skipped := v_duplicates_skipped + 1;
      CONTINUE;
    END IF;

    -- d. Cross-db dedup
    IF EXISTS (
      SELECT 1 FROM public.leads
      WHERE tenant_id = v_tenant_id AND phone_hash = v_hash
    ) THEN
      v_duplicates_skipped := v_duplicates_skipped + 1;
      CONTINUE;
    END IF;

    -- e. Track seen hashes
    v_seen_hashes := v_seen_hashes || v_hash;

    -- f. Encrypt PII
    v_phone_enc := extensions.pgp_sym_encrypt(v_normalized, v_pii_key);
    v_name := v_row->>'name';
    IF v_name IS NOT NULL AND length(trim(v_name)) > 0 THEN
      v_name_enc    := extensions.pgp_sym_encrypt(v_name, v_pii_key);
      v_name_search := lower(v_name);
    ELSE
      v_name_enc    := NULL;
      v_name_search := NULL;
    END IF;

    -- g. Map source_raw → lead_source enum
    v_source_raw := lower(trim(coalesce(v_row->>'source_raw', '')));
    IF v_source_raw = 'referral' THEN
      v_source := 'referral';
    ELSIF v_source_raw = 'associate' THEN
      v_source := 'associate';
    ELSIF v_source_raw IN ('ad', 'advertisement') THEN
      v_source := 'ad';
    ELSE
      v_source := 'walk_in';
    END IF;

    -- h. is_incomplete: true if any non-phone field is missing/blank
    v_budget_raw := v_row->>'budget_raw';
    v_is_incomplete := (
      (v_name IS NULL OR trim(coalesce(v_name, '')) = '')
      OR (v_row->>'property_type' IS NULL)
      OR (v_row->>'location' IS NULL)
      OR (v_budget_raw IS NULL OR trim(coalesce(v_budget_raw, '')) = '')
      OR (v_row->>'ticket_size' IS NULL)
      OR (v_row->>'remarks' IS NULL)
    );

    -- budget_min = budget_max = CAST(budget_raw AS bigint), NULL on failure
    BEGIN
      v_budget_min := CAST(v_budget_raw AS bigint);
      v_budget_max := v_budget_min;
    EXCEPTION WHEN OTHERS THEN
      v_budget_min := NULL;
      v_budget_max := NULL;
    END;

    -- Round-robin employee selection (i = row index, 1-based PG array)
    v_employee_id := p_employee_ids[(v_i % array_length(p_employee_ids, 1)) + 1];

    -- i. INSERT lead
    INSERT INTO public.leads (
      tenant_id,          assigned_to_user_id,
      status,             source,
      name_encrypted,     phone_encrypted,
      phone_hash,         name_search,
      property_type,      location,
      budget_min,         budget_max,
      ticket_size,        remarks,
      is_incomplete,      last_action_at
    ) VALUES (
      v_tenant_id,        v_employee_id,
      'warm',             v_source,
      v_name_enc,         v_phone_enc,
      v_hash,             v_name_search,
      v_row->>'property_type', v_row->>'location',
      v_budget_min,       v_budget_max,
      v_row->>'ticket_size',   v_row->>'remarks',
      v_is_incomplete,    now()
    )
    RETURNING id INTO v_lead_id;

    -- j. Timeline: 'imported' event with batch_id
    PERFORM public.log_timeline_event(
      v_lead_id,
      'imported'::public.timeline_event_type,
      jsonb_build_object('batch_id', v_batch_id::text)
    );

    -- k. Project match by name (case-insensitive)
    v_project_id := NULL;
    IF v_row->>'project_name' IS NOT NULL AND trim(v_row->>'project_name') <> '' THEN
      SELECT id INTO v_project_id
      FROM public.projects
      WHERE tenant_id = v_tenant_id
        AND lower(name) = lower(v_row->>'project_name')
      LIMIT 1;

      IF v_project_id IS NOT NULL THEN
        INSERT INTO public.lead_projects (lead_id, project_id)
        VALUES (v_lead_id, v_project_id)
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    -- l. Count imported
    v_imported := v_imported + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'imported',           v_imported,
    'duplicates_skipped', v_duplicates_skipped,
    'errors',             v_errors,
    'batch_id',           v_batch_id::text
  );
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_import_leads(jsonb, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bulk_import_leads(jsonb, uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.bulk_import_leads(jsonb, uuid[]) TO authenticated;

COMMENT ON FUNCTION public.bulk_import_leads(jsonb, uuid[]) IS
  'Story 6.1 — Bulk lead import with PII encryption, intra-batch + cross-db dedup, '
  'round-robin employee assignment, and timeline audit. Admin-only. SECURITY DEFINER '
  'to access vault.decrypted_secrets. Returns {imported, duplicates_skipped, errors, batch_id}.';
