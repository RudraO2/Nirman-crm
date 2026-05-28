-- Story 4.6 — Future Pool view and project-match trigger
-- FRs: FR-21 (Future Pool), FR-22 (project-match banner), FR-23 (reactivation flow)
-- Changes:
--   1. projects.property_type column (nullable text, no enum)
--   2. list_assignable_leads — add interest_type to RETURNS TABLE (additive patch)
--   3. reactivate_future_leads(jsonb) RETURNS jsonb
--   4. get_future_pool_match_count(text) RETURNS int
-- Roll-forward only. Never edit after apply.

-- ── 1. projects.property_type ─────────────────────────────────────────────────

ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS property_type text NULL;

COMMENT ON COLUMN public.projects.property_type IS
  'Story 4.6 — Optional property type that matches leads.interest_type. '
  'Values: Flat|Plot|Villa|Commercial|Studio|Penthouse. NULL = not set.';

-- ── 2. list_assignable_leads — add interest_type ──────────────────────────────
-- Must DROP then CREATE because PostgreSQL forbids changing RETURNS TABLE columns
-- with CREATE OR REPLACE. Signature (7 params) is unchanged.

DROP FUNCTION IF EXISTS public.list_assignable_leads(text, text, uuid, boolean, int, int, boolean);
DROP FUNCTION IF EXISTS public.list_assignable_leads(text, text, uuid, boolean, int, int);

CREATE OR REPLACE FUNCTION public.list_assignable_leads(
  p_q                 text    DEFAULT NULL,
  p_status            text    DEFAULT NULL,
  p_employee          uuid    DEFAULT NULL,
  p_include_archived  boolean DEFAULT false,
  p_limit             int     DEFAULT 50,
  p_offset            int     DEFAULT 0,
  p_unassigned_only   boolean DEFAULT false
)
RETURNS TABLE (
  id                  uuid,
  name                text,
  phone_last4         text,
  status              text,
  assigned_to_user_id uuid,
  assignee_username   text,
  assignment_deadline timestamptz,
  created_at          timestamptz,
  total_count         bigint,
  interest_type       text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
  v_actor_id    uuid := auth.uid();
  v_actor_role  text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id   uuid := public.auth_tenant_id();
  v_pii_key     text;
  v_q           text;
  v_q_escaped   text;
  v_phone       text;
  v_phone_hash  text;
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF v_actor_role <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT s.decrypted_secret INTO v_pii_key
    FROM vault.decrypted_secrets s
   WHERE s.name = 'lead_pii_key' LIMIT 1;
  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing';
  END IF;

  v_q := NULLIF(trim(COALESCE(p_q, '')), '');
  IF v_q IS NOT NULL THEN
    v_q_escaped := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
    v_phone := public.normalize_phone(v_q);
    IF v_phone IS NOT NULL THEN
      v_phone_hash := encode(extensions.digest(v_phone, 'sha256'), 'hex');
    END IF;
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT
      l.id,
      l.status::text                                                        AS status,
      CASE WHEN l.name_encrypted IS NOT NULL
           THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
           ELSE NULL END                                                    AS name,
      right(extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key), 4)  AS phone_last4,
      l.phone_hash,
      l.assigned_to_user_id,
      u.email_or_username                                                   AS assignee_username,
      l.assignment_deadline,
      l.created_at,
      l.interest_type
    FROM public.leads l
    LEFT JOIN public.users u ON u.id = l.assigned_to_user_id
    WHERE l.tenant_id = v_tenant_id
      AND (p_include_archived OR l.status IN ('hot','warm','cold'))
      AND (p_status IS NULL OR l.status::text = p_status)
      AND (NOT p_unassigned_only OR l.assigned_to_user_id IS NULL)
      AND (p_employee IS NULL OR l.assigned_to_user_id = p_employee)
  ),
  filtered AS (
    SELECT b.*
    FROM base b
    WHERE v_q IS NULL
       OR (b.name IS NOT NULL AND b.name ILIKE '%' || v_q_escaped || '%' ESCAPE '\')
       OR (v_phone_hash IS NOT NULL AND b.phone_hash = v_phone_hash)
  ),
  counted AS (
    SELECT count(*) AS total FROM filtered
  )
  SELECT
    f.id, f.name, f.phone_last4, f.status,
    f.assigned_to_user_id, f.assignee_username, f.assignment_deadline,
    f.created_at, c.total, f.interest_type
  FROM filtered f, counted c
  ORDER BY f.assignment_deadline ASC NULLS LAST, f.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION public.list_assignable_leads(text, text, uuid, boolean, int, int, boolean) IS
  'Story 4.6 patch — Added interest_type to RETURNS TABLE. '
  'Story 4.1 origin — Admin lead browser. Decrypts PII, returns phone_last4 + assignee + deadline + interest_type. '
  'total_count is the pre-pagination row count.';

REVOKE EXECUTE ON FUNCTION public.list_assignable_leads(text, text, uuid, boolean, int, int, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.list_assignable_leads(text, text, uuid, boolean, int, int, boolean) TO authenticated;

-- ── 3. reactivate_future_leads ────────────────────────────────────────────────
-- Admin-only bulk reactivation. For each lead: status future→warm, timeline
-- status_changed event, then assign_lead (which logs assigned/reassigned event).
-- p_leads: jsonb array of {lead_id: uuid, employee_id: uuid}
-- Returns: {reactivated: int}

CREATE OR REPLACE FUNCTION public.reactivate_future_leads(
  p_leads jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor_role  text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id   uuid := public.auth_tenant_id();
  v_entry       jsonb;
  v_lead_id     uuid;
  v_employee_id uuid;
  v_affected    int;
  v_count       int := 0;
BEGIN
  IF v_actor_role <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'tenant_missing' USING ERRCODE = '42501';
  END IF;

  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_leads)
  LOOP
    v_lead_id     := (v_entry ->> 'lead_id')::uuid;
    v_employee_id := (v_entry ->> 'employee_id')::uuid;

    -- Update status future→warm (also validates tenant scope + current status)
    UPDATE public.leads
       SET status     = 'warm',
           updated_at = now()
     WHERE id         = v_lead_id
       AND tenant_id  = v_tenant_id
       AND status     = 'future';

    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected = 0 THEN
      RAISE EXCEPTION 'lead_not_found_or_not_future: %', v_lead_id;
    END IF;

    -- Log status_changed timeline event
    PERFORM public.log_timeline_event(
      v_lead_id,
      'status_changed'::public.timeline_event_type,
      jsonb_build_object('from', 'future', 'to', 'warm', 'restored', true)
    );

    -- Assign lead (logs assigned/reassigned event internally)
    PERFORM public.assign_lead(v_lead_id, v_employee_id, NULL::timestamptz);

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('reactivated', v_count);
END;
$$;

COMMENT ON FUNCTION public.reactivate_future_leads(jsonb) IS
  'Story 4.6 — Bulk reactivate future leads. Sets status=warm, logs status_changed(restored=true), '
  'then calls assign_lead per entry. Raises on any per-lead failure with lead_id in message.';

REVOKE EXECUTE ON FUNCTION public.reactivate_future_leads(jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.reactivate_future_leads(jsonb) TO authenticated;

-- ── 4. get_future_pool_match_count ────────────────────────────────────────────
-- Returns count of future leads whose interest_type matches p_property_type.
-- Called after project creation to drive the banner redirect.

CREATE OR REPLACE FUNCTION public.get_future_pool_match_count(
  p_property_type text
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor_role  text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id   uuid := public.auth_tenant_id();
  v_count       int;
BEGIN
  IF v_actor_role <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT COUNT(*)::int
    INTO v_count
    FROM public.leads
   WHERE tenant_id     = v_tenant_id
     AND status        = 'future'
     AND interest_type = p_property_type;

  RETURN COALESCE(v_count, 0);
END;
$$;

COMMENT ON FUNCTION public.get_future_pool_match_count(text) IS
  'Story 4.6 — Count future leads matching a property_type. Used to drive the project-match banner.';

REVOKE EXECUTE ON FUNCTION public.get_future_pool_match_count(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_future_pool_match_count(text) TO authenticated;
