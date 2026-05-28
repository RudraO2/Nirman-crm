-- Story 4.1 — Admin assigns single Lead to Employee with optional deadline.
-- Adds: leads.assignment_deadline column, lead_shares table (revoke-only for now;
-- Story 4.4 adds the insert path), assign_lead RPC, list_assignable_leads RPC,
-- list_employees_for_assignment RPC, get_lead_name_for_notification RPC.
-- Roll-forward only. Never edit after apply.

-- ── 1. leads.assignment_deadline ─────────────────────────────────────────────
ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS assignment_deadline timestamptz;

COMMENT ON COLUMN public.leads.assignment_deadline IS
  'Story 4.1 — Optional admin-set follow-up-by date for an assignment. NULL = no deadline.';

-- ── 2. lead_shares table (FR-20; cascade-revoke target for Story 4.1) ─────────
CREATE TABLE IF NOT EXISTS public.lead_shares (
  id                 uuid        PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id          uuid        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  lead_id            uuid        NOT NULL REFERENCES public.leads(id)   ON DELETE CASCADE,
  recipient_user_id  uuid        NOT NULL REFERENCES public.users(id)   ON DELETE CASCADE,
  granted_by_user_id uuid        NOT NULL REFERENCES public.users(id),
  granted_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (lead_id, recipient_user_id)
);

COMMENT ON TABLE public.lead_shares IS
  'Story 4.1 — Lead share grants. Created here for cascade-revoke on reassign; Story 4.4 adds the insert path.';

ALTER TABLE public.lead_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_shares FORCE  ROW LEVEL SECURITY;

CREATE POLICY lead_shares_tenant_select ON public.lead_shares
  FOR SELECT TO authenticated
  USING (tenant_id = public.auth_tenant_id());

-- Insert/update/delete intentionally NOT granted yet — assign_lead (SECURITY DEFINER)
-- handles the delete; Story 4.4 will add a share_lead RPC for the insert path.

CREATE INDEX IF NOT EXISTS lead_shares_lead_id_idx
  ON public.lead_shares (lead_id);

CREATE INDEX IF NOT EXISTS lead_shares_recipient_idx
  ON public.lead_shares (recipient_user_id);

-- ── 3. assign_lead(lead_id, target_user_id, deadline) ────────────────────────
CREATE OR REPLACE FUNCTION public.assign_lead(
  p_lead_id        uuid,
  p_target_user_id uuid,
  p_deadline       timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor_id   uuid := auth.uid();
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
  v_prev_user  uuid;
  v_prev_uname text;
  v_target     RECORD;
  v_share      RECORD;
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF v_actor_role <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'tenant_missing' USING ERRCODE = '42501';
  END IF;

  -- Lock the lead row (tenant-scoped)
  SELECT assigned_to_user_id
    INTO v_prev_user
    FROM public.leads
   WHERE id = p_lead_id AND tenant_id = v_tenant_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'lead_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- Validate target employee
  SELECT id, role, is_active, email_or_username
    INTO v_target
    FROM public.users
   WHERE id = p_target_user_id AND tenant_id = v_tenant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'target_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_target.role <> 'employee' OR v_target.is_active = false THEN
    RAISE EXCEPTION 'target_not_assignable' USING ERRCODE = '22023';
  END IF;

  -- Apply assignment + deadline
  UPDATE public.leads
     SET assigned_to_user_id = p_target_user_id,
         assignment_deadline = p_deadline,
         updated_at          = now()
   WHERE id = p_lead_id AND tenant_id = v_tenant_id;

  -- Cascade-revoke any active shares (system actor, NULL actor_user_id)
  FOR v_share IN
    DELETE FROM public.lead_shares
     WHERE lead_id = p_lead_id
   RETURNING recipient_user_id
  LOOP
    INSERT INTO public.lead_timeline (
      tenant_id, lead_id, actor_user_id, actor_role, event_type, payload, occurred_at
    ) VALUES (
      v_tenant_id, p_lead_id, NULL, 'system',
      'share_revoked',
      jsonb_build_object(
        'recipient_user_id', v_share.recipient_user_id,
        'reason',            'cascade_on_assign'
      ),
      now()
    );
  END LOOP;

  -- Emit assigned / reassigned / (no-op for self-reassign)
  IF v_prev_user IS NULL THEN
    PERFORM public.log_timeline_event(
      p_lead_id,
      'assigned'::public.timeline_event_type,
      jsonb_build_object(
        'to',          p_target_user_id,
        'to_username', v_target.email_or_username,
        'deadline',    p_deadline
      )
    );
  ELSIF v_prev_user <> p_target_user_id THEN
    SELECT email_or_username INTO v_prev_uname
      FROM public.users WHERE id = v_prev_user;
    PERFORM public.log_timeline_event(
      p_lead_id,
      'reassigned'::public.timeline_event_type,
      jsonb_build_object(
        'from',          v_prev_user,
        'from_username', v_prev_uname,
        'to',            p_target_user_id,
        'to_username',   v_target.email_or_username,
        'deadline',      p_deadline
      )
    );
  END IF;
  -- else: same employee re-confirmed; deadline still updated above, no timeline noise.

  RETURN jsonb_build_object(
    'lead_id',      p_lead_id,
    'prev_user_id', v_prev_user,
    'new_user_id',  p_target_user_id,
    'deadline',     p_deadline
  );
END;
$$;

COMMENT ON FUNCTION public.assign_lead(uuid, uuid, timestamptz) IS
  'Story 4.1 — Admin-only assign/reassign with cascade-revoke of lead_shares. Returns {lead_id, prev_user_id, new_user_id, deadline}.';

REVOKE EXECUTE ON FUNCTION public.assign_lead(uuid, uuid, timestamptz) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.assign_lead(uuid, uuid, timestamptz) TO authenticated;

-- ── 4. list_assignable_leads — admin lead browser feed ───────────────────────
CREATE OR REPLACE FUNCTION public.list_assignable_leads(
  p_q                 text    DEFAULT NULL,
  p_status            text    DEFAULT NULL,
  p_employee          uuid    DEFAULT NULL,
  p_include_archived  boolean DEFAULT false,
  p_limit             int     DEFAULT 50,
  p_offset            int     DEFAULT 0
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
  total_count         bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
  v_actor_id   uuid := auth.uid();
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
  v_pii_key    text;
  v_q          text;
  v_phone      text;
  v_phone_hash text;
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
    v_phone := public.normalize_phone(v_q);
    IF v_phone IS NOT NULL THEN
      v_phone_hash := encode(extensions.digest(v_phone, 'sha256'), 'hex');
    END IF;
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT
      l.id,
      l.status::text                                                 AS status,
      CASE WHEN l.name_encrypted IS NOT NULL
           THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
           ELSE NULL END                                             AS name,
      right(extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key), 4) AS phone_last4,
      l.phone_hash,
      l.assigned_to_user_id,
      u.email_or_username                                            AS assignee_username,
      l.assignment_deadline,
      l.created_at
    FROM public.leads l
    LEFT JOIN public.users u ON u.id = l.assigned_to_user_id
    WHERE l.tenant_id = v_tenant_id
      AND (p_include_archived OR l.status IN ('hot','warm','cold'))
      AND (p_status IS NULL OR l.status::text = p_status)
      AND (p_employee IS NULL OR l.assigned_to_user_id = p_employee)
  ),
  filtered AS (
    SELECT b.*
    FROM base b
    WHERE v_q IS NULL
       OR (b.name IS NOT NULL AND b.name ILIKE '%' || v_q || '%')
       OR (v_phone_hash IS NOT NULL AND b.phone_hash = v_phone_hash)
  ),
  counted AS (
    SELECT count(*) AS total FROM filtered
  )
  SELECT
    f.id, f.name, f.phone_last4, f.status,
    f.assigned_to_user_id, f.assignee_username, f.assignment_deadline,
    f.created_at, c.total
  FROM filtered f, counted c
  ORDER BY f.assignment_deadline ASC NULLS LAST, f.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION public.list_assignable_leads(text, text, uuid, boolean, int, int) IS
  'Story 4.1 — Admin lead browser. Decrypts PII, returns phone_last4 + assignee + deadline. total_count is the pre-pagination row count.';

REVOKE EXECUTE ON FUNCTION public.list_assignable_leads(text, text, uuid, boolean, int, int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.list_assignable_leads(text, text, uuid, boolean, int, int) TO authenticated;

-- ── 5. list_employees_for_assignment — admin dropdown feed ───────────────────
CREATE OR REPLACE FUNCTION public.list_employees_for_assignment()
RETURNS TABLE (id uuid, username text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
BEGIN
  IF v_actor_role <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT u.id, u.email_or_username
    FROM public.users u
   WHERE u.tenant_id = v_tenant_id
     AND u.role      = 'employee'
     AND u.is_active = true
   ORDER BY u.email_or_username ASC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_employees_for_assignment() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.list_employees_for_assignment() TO authenticated;

-- ── 6. get_lead_name_for_notification — edge-fn helper (admin-only) ──────────
-- Lets the send-assignment-notification edge fn fetch the lead's decrypted name
-- without handling the PII key directly.
CREATE OR REPLACE FUNCTION public.get_lead_name_for_notification(p_lead_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_pii_key    text;
  v_name       text;
BEGIN
  -- Allow admin (UI) OR service_role (edge fn) callers
  IF v_actor_role NOT IN ('admin', 'service_role') AND
     COALESCE((auth.jwt() ->> 'role'), '') <> 'service_role' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT s.decrypted_secret INTO v_pii_key
    FROM vault.decrypted_secrets s
   WHERE s.name = 'lead_pii_key' LIMIT 1;
  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing';
  END IF;

  SELECT CASE WHEN l.name_encrypted IS NOT NULL
              THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
              ELSE 'New lead' END
    INTO v_name
    FROM public.leads l
   WHERE l.id = p_lead_id;

  RETURN COALESCE(v_name, 'New lead');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_lead_name_for_notification(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_lead_name_for_notification(uuid) TO authenticated, service_role;
