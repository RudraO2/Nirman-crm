-- Story 4.1 code-review patches.
--   P1: list_assignable_leads — escape ILIKE wildcards in search input (no user-driven %).
--   P2: list_assignable_leads — add p_unassigned_only flag (was filtered client-side post-pagination, broken).
--   P3: assign_lead — direct-insert share_revoked rows must also write to domain_events
--                     (log_timeline_event helper writes both; the cascade loop bypassed it).
-- Roll-forward only. Never edit after apply.

-- ── P1 + P2: list_assignable_leads ──────────────────────────────────────────
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
  total_count         bigint
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
    -- P1: escape ILIKE wildcards so `%` / `_` from the user are literal.
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
    f.created_at, c.total
  FROM filtered f, counted c
  ORDER BY f.assignment_deadline ASC NULLS LAST, f.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_assignable_leads(text, text, uuid, boolean, int, int, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.list_assignable_leads(text, text, uuid, boolean, int, int, boolean) TO authenticated;

-- ── P3: assign_lead — cascade-revoke also writes domain_events ────────────────
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
  v_actor_id    uuid := auth.uid();
  v_actor_role  text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id   uuid := public.auth_tenant_id();
  v_prev_user   uuid;
  v_prev_uname  text;
  v_target      RECORD;
  v_share       RECORD;
  v_timeline_id uuid;
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

  SELECT assigned_to_user_id
    INTO v_prev_user
    FROM public.leads
   WHERE id = p_lead_id AND tenant_id = v_tenant_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'lead_not_found' USING ERRCODE = 'P0002';
  END IF;

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

  UPDATE public.leads
     SET assigned_to_user_id = p_target_user_id,
         assignment_deadline = p_deadline,
         updated_at          = now()
   WHERE id = p_lead_id AND tenant_id = v_tenant_id;

  -- Cascade-revoke shares (system actor) — mirror log_timeline_event by writing
  -- BOTH lead_timeline AND domain_events so downstream consumers stay in sync.
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
    )
    RETURNING id INTO v_timeline_id;

    INSERT INTO public.domain_events (
      tenant_id, event_type, payload, occurred_at
    ) VALUES (
      v_tenant_id,
      'share_revoked',
      jsonb_build_object(
        'lead_id',       p_lead_id,
        'actor_user_id', NULL,
        'actor_role',    'system',
        'timeline_id',   v_timeline_id,
        'event_payload', jsonb_build_object(
          'recipient_user_id', v_share.recipient_user_id,
          'reason',            'cascade_on_assign'
        )
      ),
      now()
    );
  END LOOP;

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

  RETURN jsonb_build_object(
    'lead_id',      p_lead_id,
    'prev_user_id', v_prev_user,
    'new_user_id',  p_target_user_id,
    'deadline',     p_deadline
  );
END;
$$;
