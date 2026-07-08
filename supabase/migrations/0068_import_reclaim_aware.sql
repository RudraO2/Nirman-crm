-- 0068_import_reclaim_aware.sql
-- Story 13.6 (Epic 13) — FR-47. Excel import honours the 90-day lock / reclaim rules.
--
-- check_phone_hashes now returns lock-state (locked boolean) so the import preview can show
-- locked-skip vs reclaimable counts. bulk_import_leads cross-db step classifies each existing
-- phone: locked → skip; reclaimable (≥90d OR owner inactive ≥30d) → reclaim-in-place (reassign
-- to the round-robin employee, reset lock, log lead_reclaimed); none → insert new (now sets
-- lock_started_at). Imported NEW leads do not auto-generate a customer_code (codes are issued at
-- interactive registration; an imported lead gets one when first edited) — acceptable for V2.
--
-- Bodies reproduced from 0052; only the dedup classification + counters + insert column changed.
-- bulk_import_leads keeps its (jsonb, uuid[]) signature → CREATE OR REPLACE. check_phone_hashes
-- changes its RETURNS shape → DROP + CREATE.
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

-- 1. check_phone_hashes → (phone_hash, locked) -------------------------------
DROP FUNCTION IF EXISTS public.check_phone_hashes(text[]);

CREATE OR REPLACE FUNCTION public.check_phone_hashes(p_hashes text[])
RETURNS TABLE (phone_hash text, locked boolean)
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
    RAISE EXCEPTION 'admin_required: only admins may call check_phone_hashes' USING ERRCODE = 'P0001';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  RETURN QUERY
    SELECT l.phone_hash,
           (now() < COALESCE(l.lock_started_at, l.created_at) + interval '90 days'
            AND l.last_action_at > now() - interval '30 days') AS locked
    FROM public.leads l
    WHERE l.tenant_id = v_tenant_id
      AND l.phone_hash = ANY(p_hashes);
END;
$$;

REVOKE ALL ON FUNCTION public.check_phone_hashes(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_phone_hashes(text[]) TO authenticated;

COMMENT ON FUNCTION public.check_phone_hashes(text[]) IS
  'Story 6.1 + 13.6 — for each existing phone_hash in the tenant, returns whether it is currently locked (≤90d & owner active ≤30d). Admin-only. Powers the import preview (locked-skip vs reclaimable).';

-- 2. bulk_import_leads — reclaim-aware ---------------------------------------
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
  v_existing          RECORD;
  v_locked            boolean;
  v_imported          integer := 0;
  v_reclaimed         integer := 0;
  v_duplicates_skipped integer := 0;
  v_errors            integer := 0;
BEGIN
  v_role := (auth.jwt() -> 'app_metadata') ->> 'role';
  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'admin_required: only admins may call bulk_import_leads' USING ERRCODE = 'P0001';
  END IF;
  v_tenant_id := public.auth_tenant_id();

  IF p_employee_ids IS NULL OR array_length(p_employee_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'employee_ids_required: at least one employee must be selected' USING ERRCODE = 'P0001';
  END IF;

  SELECT decrypted_secret INTO v_pii_key
  FROM vault.decrypted_secrets WHERE name = 'lead_pii_key' LIMIT 1;
  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing: vault secret lead_pii_key not configured' USING ERRCODE = 'P0003';
  END IF;

  v_total_rows := jsonb_array_length(p_rows);

  FOR v_i IN 0..v_total_rows - 1
  LOOP
    v_row := p_rows->v_i;

    v_normalized := public.normalize_phone(v_row->>'phone_raw');
    IF v_normalized IS NULL THEN
      v_errors := v_errors + 1;
      CONTINUE;
    END IF;

    v_hash := encode(extensions.digest(v_normalized, 'sha256'), 'hex');

    -- intra-batch dedup
    IF v_hash = ANY(v_seen_hashes) THEN
      v_duplicates_skipped := v_duplicates_skipped + 1;
      CONTINUE;
    END IF;

    v_employee_id := p_employee_ids[(v_i % array_length(p_employee_ids, 1)) + 1];

    -- cross-db: classify locked vs reclaimable (Story 13.6)
    SELECT id, assigned_to_user_id, lock_started_at, last_action_at, created_at
      INTO v_existing
      FROM public.leads
     WHERE tenant_id = v_tenant_id AND phone_hash = v_hash
     ORDER BY created_at ASC
     LIMIT 1;
    IF FOUND THEN
      v_locked := (now() < COALESCE(v_existing.lock_started_at, v_existing.created_at) + interval '90 days')
                  AND (v_existing.last_action_at > now() - interval '30 days');
      IF v_locked THEN
        v_duplicates_skipped := v_duplicates_skipped + 1;
        v_seen_hashes := v_seen_hashes || v_hash;
        CONTINUE;
      ELSE
        -- reclaim-in-place to the round-robin employee
        UPDATE public.leads
           SET assigned_to_user_id = v_employee_id,
               lock_started_at     = now(),
               status              = 'warm',
               last_action_at      = now(),
               updated_at          = now()
         WHERE id = v_existing.id;
        PERFORM public.log_timeline_event(
          v_existing.id, 'lead_reclaimed'::public.timeline_event_type,
          jsonb_build_object('from_user_id', v_existing.assigned_to_user_id, 'to_user_id', v_employee_id, 'batch_id', v_batch_id::text)
        );
        v_reclaimed := v_reclaimed + 1;
        v_seen_hashes := v_seen_hashes || v_hash;
        CONTINUE;
      END IF;
    END IF;

    v_seen_hashes := v_seen_hashes || v_hash;

    -- encrypt PII
    v_phone_enc := extensions.pgp_sym_encrypt(v_normalized, v_pii_key);
    v_name := v_row->>'name';
    IF v_name IS NOT NULL AND length(trim(v_name)) > 0 THEN
      v_name_enc    := extensions.pgp_sym_encrypt(v_name, v_pii_key);
      v_name_search := lower(v_name);
    ELSE
      v_name_enc    := NULL;
      v_name_search := NULL;
    END IF;

    -- map source
    v_source_raw := lower(trim(coalesce(v_row->>'source_raw', '')));
    IF v_source_raw = 'referral' THEN
      v_source := 'referral';
    ELSIF v_source_raw = 'associate' THEN
      v_source := 'associate';
    ELSIF v_source_raw IN ('ad', 'advertisement') THEN
      v_source := 'ad';
    ELSIF v_source_raw IN ('cold_call', 'cold call', 'coldcall') THEN
      v_source := 'cold_call';
    ELSIF v_source_raw IN ('employee_referral', 'employee referral', 'emp_ref') THEN
      v_source := 'employee_referral';
    ELSE
      v_source := 'walk_in';
    END IF;

    v_budget_raw := v_row->>'budget_raw';
    v_is_incomplete := (
      (v_name IS NULL OR trim(coalesce(v_name, '')) = '')
      OR (v_row->>'property_type' IS NULL)
      OR (v_row->>'location' IS NULL)
      OR (v_budget_raw IS NULL OR trim(coalesce(v_budget_raw, '')) = '')
      OR (v_row->>'ticket_size' IS NULL)
      OR (v_row->>'remarks' IS NULL)
    );

    BEGIN
      v_budget_min := CAST(v_budget_raw AS bigint);
      v_budget_max := v_budget_min;
    EXCEPTION WHEN OTHERS THEN
      v_budget_min := NULL;
      v_budget_max := NULL;
    END;

    INSERT INTO public.leads (
      tenant_id,          assigned_to_user_id,
      status,             source,
      name_encrypted,     phone_encrypted,
      phone_hash,         name_search,
      lock_started_at,
      property_type,      location,
      budget_min,         budget_max,
      ticket_size,        remarks,
      is_incomplete,      last_action_at
    ) VALUES (
      v_tenant_id,        v_employee_id,
      'warm',             v_source,
      v_name_enc,         v_phone_enc,
      v_hash,             v_name_search,
      now(),
      v_row->>'property_type', v_row->>'location',
      v_budget_min,       v_budget_max,
      v_row->>'ticket_size',   v_row->>'remarks',
      v_is_incomplete,    now()
    )
    RETURNING id INTO v_lead_id;

    PERFORM public.log_timeline_event(
      v_lead_id, 'imported'::public.timeline_event_type,
      jsonb_build_object('batch_id', v_batch_id::text)
    );

    v_project_id := NULL;
    IF v_row->>'project_name' IS NOT NULL AND trim(v_row->>'project_name') <> '' THEN
      SELECT id INTO v_project_id
      FROM public.projects
      WHERE tenant_id = v_tenant_id AND lower(name) = lower(v_row->>'project_name')
      LIMIT 1;
      IF v_project_id IS NOT NULL THEN
        INSERT INTO public.lead_projects (lead_id, project_id)
        VALUES (v_lead_id, v_project_id)
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    v_imported := v_imported + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'imported',           v_imported,
    'reclaimed',          v_reclaimed,
    'duplicates_skipped', v_duplicates_skipped,
    'errors',             v_errors,
    'batch_id',           v_batch_id::text
  );
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_import_leads(jsonb, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bulk_import_leads(jsonb, uuid[]) TO authenticated;

COMMENT ON FUNCTION public.bulk_import_leads(jsonb, uuid[]) IS
  'Story 6.1 + 13.6 — bulk import, lock-aware: locked phones skipped, reclaimable phones reassigned in place (lead_reclaimed), new phones inserted with lock_started_at. Admin-only. Returns {imported, reclaimed, duplicates_skipped, errors, batch_id}.';

COMMIT;
