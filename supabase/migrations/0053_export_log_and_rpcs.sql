-- Stories 6.2 + 6.3 — Excel Export + Export Audit Log
-- Creates export_log table, get_export_count(), and export_leads_data() RPC.
-- export_leads_data inserts into export_log BEFORE returning rows (atomic audit).
-- Roll-forward only. Never edit after apply.

-- ────────────────────────────────────────────────────────────────────────────
-- export_log — append-only audit table (no UPDATE / DELETE policy)
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.export_log (
  id           uuid        PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id    uuid        NOT NULL REFERENCES public.tenants(id)  ON DELETE RESTRICT,
  admin_id     uuid        NOT NULL REFERENCES public.users(id)    ON DELETE RESTRICT,
  exported_at  timestamptz NOT NULL DEFAULT now(),
  filters_json jsonb       NOT NULL DEFAULT '{}',
  row_count    integer     NOT NULL,
  file_name    text        NOT NULL
);

ALTER TABLE public.export_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_log FORCE ROW LEVEL SECURITY;

CREATE POLICY export_log_select ON public.export_log
  FOR SELECT TO authenticated
  USING (tenant_id = public.auth_tenant_id());

CREATE POLICY export_log_insert ON public.export_log
  FOR INSERT TO authenticated
  WITH CHECK (tenant_id = public.auth_tenant_id());

-- No UPDATE or DELETE policy — FORCE RLS default-denies both.

GRANT SELECT, INSERT ON public.export_log TO authenticated;

CREATE INDEX ON public.export_log (tenant_id, exported_at DESC);

-- ────────────────────────────────────────────────────────────────────────────
-- get_export_count — preview row count matching the given filters
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_export_count(
  p_status        text    DEFAULT NULL,
  p_employee_id   uuid    DEFAULT NULL,
  p_project_id    uuid    DEFAULT NULL,
  p_property_type text    DEFAULT NULL,
  p_date_from     date    DEFAULT NULL,
  p_date_to       date    DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_count     integer;
BEGIN
  v_tenant_id := public.auth_tenant_id();

  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied: admin role required' USING ERRCODE = '42501';
  END IF;

  SELECT COUNT(*)::integer INTO v_count
  FROM public.leads l
  WHERE l.tenant_id = v_tenant_id
    AND (p_status        IS NULL OR l.status::text          = p_status)
    AND (p_employee_id   IS NULL OR l.assigned_to_user_id   = p_employee_id)
    AND (p_project_id    IS NULL OR EXISTS (
          SELECT 1 FROM public.lead_projects lp
          WHERE lp.lead_id = l.id AND lp.project_id = p_project_id))
    AND (p_property_type IS NULL OR l.property_type         = p_property_type)
    AND (p_date_from     IS NULL OR l.created_at::date      >= p_date_from)
    AND (p_date_to       IS NULL OR l.created_at::date      <= p_date_to);

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.get_export_count(text, uuid, uuid, text, date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_export_count(text, uuid, uuid, text, date, date) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_export_count(text, uuid, uuid, text, date, date) TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- export_leads_data — insert export_log then stream decrypted lead rows
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.export_leads_data(
  p_file_name     text,
  p_status        text    DEFAULT NULL,
  p_employee_id   uuid    DEFAULT NULL,
  p_project_id    uuid    DEFAULT NULL,
  p_property_type text    DEFAULT NULL,
  p_date_from     date    DEFAULT NULL,
  p_date_to       date    DEFAULT NULL
)
RETURNS TABLE (
  lead_name         text,
  phone             text,
  status            text,
  source            text,
  property_type     text,
  location          text,
  budget_min        bigint,
  budget_max        bigint,
  ticket_size       text,
  remarks           text,
  interest_type     text,
  is_incomplete     boolean,
  visit_date        timestamptz,
  next_followup_at  timestamptz,
  created_at        timestamptz,
  assigned_employee text,
  timeline_summary  text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_pii_key   text;
  v_row_count integer;
  v_tz        text;
BEGIN
  v_tenant_id := public.auth_tenant_id();

  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied: admin role required' USING ERRCODE = '42501';
  END IF;

  -- Read PII encryption key from Vault (SECURITY DEFINER grants postgres-level access)
  SELECT decrypted_secret INTO v_pii_key
  FROM vault.decrypted_secrets
  WHERE name = 'lead_pii_key'
  LIMIT 1;

  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing: vault secret lead_pii_key not configured'
      USING ERRCODE = 'P0003';
  END IF;

  -- Tenant timezone (fallback Asia/Kolkata)
  SELECT t.timezone INTO v_tz
  FROM public.tenants t
  WHERE t.id = v_tenant_id;

  IF v_tz IS NULL OR trim(v_tz) = '' THEN
    v_tz := 'Asia/Kolkata';
  END IF;

  -- Count rows matching filters (for audit log)
  SELECT COUNT(*)::integer INTO v_row_count
  FROM public.leads l
  WHERE l.tenant_id = v_tenant_id
    AND (p_status        IS NULL OR l.status::text          = p_status)
    AND (p_employee_id   IS NULL OR l.assigned_to_user_id   = p_employee_id)
    AND (p_project_id    IS NULL OR EXISTS (
          SELECT 1 FROM public.lead_projects lp
          WHERE lp.lead_id = l.id AND lp.project_id = p_project_id))
    AND (p_property_type IS NULL OR l.property_type         = p_property_type)
    AND (p_date_from     IS NULL OR l.created_at::date      >= p_date_from)
    AND (p_date_to       IS NULL OR l.created_at::date      <= p_date_to);

  -- Insert audit record BEFORE returning data
  INSERT INTO public.export_log (
    tenant_id, admin_id, exported_at, filters_json, row_count, file_name
  ) VALUES (
    v_tenant_id,
    auth.uid(),
    now(),
    jsonb_build_object(
      'status',        p_status,
      'employee_id',   p_employee_id,
      'project_id',    p_project_id,
      'property_type', p_property_type,
      'date_from',     p_date_from,
      'date_to',       p_date_to
    ),
    v_row_count,
    p_file_name
  );

  RETURN QUERY
  SELECT
    CASE WHEN l.name_encrypted IS NOT NULL
         THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
         ELSE NULL
    END                                                              AS lead_name,
    extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key)        AS phone,
    l.status::text,
    l.source::text,
    l.property_type,
    l.location,
    l.budget_min,
    l.budget_max,
    l.ticket_size,
    l.remarks,
    l.interest_type,
    l.is_incomplete,
    l.visit_date,
    l.next_followup_at,
    l.created_at,
    u.email_or_username                                              AS assigned_employee,
    (
      SELECT string_agg(
               lt.event_type::text
               || ' ('
               || to_char(lt.occurred_at AT TIME ZONE v_tz, 'DD-Mon HH24:MI')
               || ')',
               ' | '
               ORDER BY lt.occurred_at DESC
             )
      FROM (
        SELECT event_type, occurred_at
        FROM public.lead_timeline
        WHERE lead_id = l.id
        ORDER BY occurred_at DESC
        LIMIT 3
      ) lt
    )                                                                AS timeline_summary
  FROM public.leads l
  LEFT JOIN public.users u ON u.id = l.assigned_to_user_id
  WHERE l.tenant_id = v_tenant_id
    AND (p_status        IS NULL OR l.status::text          = p_status)
    AND (p_employee_id   IS NULL OR l.assigned_to_user_id   = p_employee_id)
    AND (p_project_id    IS NULL OR EXISTS (
          SELECT 1 FROM public.lead_projects lp
          WHERE lp.lead_id = l.id AND lp.project_id = p_project_id))
    AND (p_property_type IS NULL OR l.property_type         = p_property_type)
    AND (p_date_from     IS NULL OR l.created_at::date      >= p_date_from)
    AND (p_date_to       IS NULL OR l.created_at::date      <= p_date_to)
  ORDER BY l.created_at DESC
  LIMIT 10000;
END;
$$;

REVOKE ALL ON FUNCTION public.export_leads_data(text, text, uuid, uuid, text, date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.export_leads_data(text, text, uuid, uuid, text, date, date) FROM anon;
GRANT  EXECUTE ON FUNCTION public.export_leads_data(text, text, uuid, uuid, text, date, date) TO authenticated;
