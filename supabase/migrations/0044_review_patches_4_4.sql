-- Story 4.4 code-review patches.
--   P1: share_lead — add FOR UPDATE lock on leads row to close race with assign_lead
--   P2: revoke_share — add tenant_id guard to DELETE (belt-and-suspenders vs cross-tenant)
--   P3: list_employees_for_share — exclude caller server-side (defense-in-depth)
--   P4: get_lead_by_id — COALESCE is_shared so NULL assigned_to → false, not NULL
--   P5: get_lead_timeline — extend ownership gate to shared-lead recipients (AC-5 fix)
-- Roll-forward only. Never edit after apply.

-- ── P1: share_lead — FOR UPDATE lock prevents race with assign_lead ───────────
CREATE OR REPLACE FUNCTION public.share_lead(
  p_lead_id           uuid,
  p_recipient_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor_id   uuid := auth.uid();
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
  v_recipient  RECORD;
  v_inserted   int;
  v_lead_id    uuid;
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF v_actor_role <> 'employee' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'tenant_missing' USING ERRCODE = '42501';
  END IF;

  -- Lock the lead row first (mirrors assign_lead pattern) to close the race where
  -- assign_lead cascade-deletes shares between our ownership check and our INSERT.
  SELECT id INTO v_lead_id
    FROM public.leads
   WHERE id                  = p_lead_id
     AND tenant_id           = v_tenant_id
     AND assigned_to_user_id = v_actor_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'lead_not_found_or_not_owner' USING ERRCODE = 'P0002';
  END IF;

  IF p_recipient_user_id = v_actor_id THEN
    RAISE EXCEPTION 'cannot_share_with_self' USING ERRCODE = '22023';
  END IF;

  SELECT id, role, is_active, email_or_username
    INTO v_recipient
    FROM public.users
   WHERE id = p_recipient_user_id AND tenant_id = v_tenant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'recipient_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_recipient.role <> 'employee' OR v_recipient.is_active = false THEN
    RAISE EXCEPTION 'recipient_not_eligible' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.lead_shares (
    tenant_id, lead_id, recipient_user_id, granted_by_user_id, granted_at
  ) VALUES (
    v_tenant_id, p_lead_id, p_recipient_user_id, v_actor_id, now()
  )
  ON CONFLICT (lead_id, recipient_user_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  IF v_inserted > 0 THEN
    PERFORM public.log_timeline_event(
      p_lead_id,
      'shared'::public.timeline_event_type,
      jsonb_build_object(
        'recipient_user_id',  p_recipient_user_id,
        'recipient_username', v_recipient.email_or_username
      )
    );
  END IF;
END;
$$;

COMMENT ON FUNCTION public.share_lead(uuid, uuid) IS
  'Story 4.4 (patched P1) — Employee-only. FOR UPDATE lock on leads row prevents race with assign_lead cascade-revoke. Idempotent (ON CONFLICT DO NOTHING). Logs shared timeline only on first insert.';

REVOKE EXECUTE ON FUNCTION public.share_lead(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.share_lead(uuid, uuid) TO authenticated;

-- ── P2: revoke_share — add tenant_id guard to DELETE ─────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_share(
  p_lead_id           uuid,
  p_recipient_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor_id   uuid := auth.uid();
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
  v_deleted    int;
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'tenant_missing' USING ERRCODE = '42501';
  END IF;

  IF v_actor_role = 'employee' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.leads
       WHERE id                  = p_lead_id
         AND tenant_id           = v_tenant_id
         AND assigned_to_user_id = v_actor_id
    ) THEN
      RAISE EXCEPTION 'lead_not_found_or_not_owner' USING ERRCODE = 'P0002';
    END IF;
  ELSIF v_actor_role = 'admin' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.leads
       WHERE id = p_lead_id AND tenant_id = v_tenant_id
    ) THEN
      RAISE EXCEPTION 'lead_not_found' USING ERRCODE = 'P0002';
    END IF;
  ELSE
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  -- P2: add tenant_id to DELETE for belt-and-suspenders cross-tenant safety.
  DELETE FROM public.lead_shares
   WHERE lead_id           = p_lead_id
     AND recipient_user_id = p_recipient_user_id
     AND tenant_id         = v_tenant_id;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  IF v_deleted > 0 THEN
    PERFORM public.log_timeline_event(
      p_lead_id,
      'share_revoked'::public.timeline_event_type,
      jsonb_build_object(
        'recipient_user_id', p_recipient_user_id,
        'revoked_by',        v_actor_id
      )
    );
  END IF;
END;
$$;

COMMENT ON FUNCTION public.revoke_share(uuid, uuid) IS
  'Story 4.4 (patched P2) — Employee (owner) or admin. Revokes a lead share. DELETE now scoped by tenant_id. Idempotent. Logs share_revoked only when row actually deleted.';

REVOKE EXECUTE ON FUNCTION public.revoke_share(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.revoke_share(uuid, uuid) TO authenticated;

-- ── P3: list_employees_for_share — exclude caller server-side ─────────────────
CREATE OR REPLACE FUNCTION public.list_employees_for_share()
RETURNS TABLE (id uuid, username text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor_id   uuid := auth.uid();
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF v_actor_role NOT IN ('employee', 'admin') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT u.id, u.email_or_username
    FROM public.users u
   WHERE u.tenant_id = v_tenant_id
     AND u.role      = 'employee'
     AND u.is_active = true
     AND u.id        <> v_actor_id
   ORDER BY u.email_or_username ASC;
END;
$$;

COMMENT ON FUNCTION public.list_employees_for_share() IS
  'Story 4.4 (patched P3) — Employee or admin. Returns active employees in tenant excluding the caller (server-side self-exclusion).';

REVOKE EXECUTE ON FUNCTION public.list_employees_for_share() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.list_employees_for_share() TO authenticated;

-- ── P4: get_lead_by_id — COALESCE is_shared to handle NULL assigned_to ────────
CREATE OR REPLACE FUNCTION public.get_lead_by_id(p_lead_id uuid)
RETURNS TABLE (
  id                 uuid,
  status             text,
  name               text,
  phone              text,
  source             text,
  property_type      text,
  location           text,
  budget_min         bigint,
  budget_max         bigint,
  ticket_size        text,
  visit_date         timestamptz,
  next_followup_at   timestamptz,
  is_incomplete      boolean,
  pending_outcome_at timestamptz,
  last_action_at     timestamptz,
  created_at         timestamptz,
  urgency_score      int,
  project_ids        uuid[],
  remarks            text,
  is_shared          boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_pii_key text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT s.decrypted_secret INTO v_pii_key
  FROM vault.decrypted_secrets s
  WHERE s.name = 'lead_pii_key'
  LIMIT 1;

  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing';
  END IF;

  RETURN QUERY
  SELECT
    l.id,
    l.status::text,
    CASE WHEN l.name_encrypted IS NOT NULL
         THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
         ELSE NULL END,
    extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key),
    l.source::text,
    l.property_type,
    l.location,
    l.budget_min,
    l.budget_max,
    l.ticket_size,
    l.visit_date,
    l.next_followup_at,
    l.is_incomplete,
    l.pending_outcome_at,
    l.last_action_at,
    l.created_at,
    CASE
      WHEN l.pending_outcome_at IS NOT NULL                                THEN 1000
      WHEN l.status = 'hot' AND l.next_followup_at IS NOT NULL
           AND l.next_followup_at < now()                                  THEN  700
      WHEN l.status = 'hot' AND l.next_followup_at IS NOT NULL
           AND l.next_followup_at::date = current_date                     THEN  600
      WHEN l.status = 'hot'                                                THEN  500
      WHEN l.status = 'warm' AND l.next_followup_at IS NOT NULL
           AND l.next_followup_at < now()                                  THEN  400
      WHEN l.status = 'warm'                                               THEN  300
      WHEN l.status = 'cold' AND l.next_followup_at IS NOT NULL
           AND l.next_followup_at < now()                                  THEN  250
      WHEN l.status = 'cold'                                               THEN  200
      WHEN l.last_action_at < now() - interval '7 days'                   THEN   50
      ELSE 100
    END::int,
    COALESCE(
      (SELECT array_agg(lp.project_id ORDER BY lp.project_id)
         FROM public.lead_projects lp
        WHERE lp.lead_id = l.id),
      '{}'::uuid[]
    ),
    l.remarks,
    -- P4: COALESCE so NULL assigned_to (unassigned lead) yields false not NULL
    COALESCE((l.assigned_to_user_id <> v_user_id), false)
  FROM public.leads l
  WHERE l.id = p_lead_id
    AND (
      l.assigned_to_user_id = v_user_id
      OR EXISTS (
        SELECT 1 FROM public.lead_shares ls
         WHERE ls.lead_id = l.id AND ls.recipient_user_id = v_user_id
      )
    );
END;
$$;

COMMENT ON FUNCTION public.get_lead_by_id(uuid) IS
  'Story 4.4 (patched P4) — Single lead fetch. Returns owned OR shared leads. is_shared uses COALESCE to avoid NULL when assigned_to is NULL.';

REVOKE EXECUTE ON FUNCTION public.get_lead_by_id(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_lead_by_id(uuid) TO authenticated;

-- ── P5: get_lead_timeline — extend gate to shared-lead recipients (AC-5) ──────
CREATE OR REPLACE FUNCTION public.get_lead_timeline(p_lead_id uuid)
RETURNS TABLE (
  id            uuid,
  event_type    text,
  actor_user_id uuid,
  actor_role    text,
  actor_name    text,
  payload       jsonb,
  occurred_at   timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Ownership gate: lead must be assigned to caller OR caller is an active recipient.
  IF NOT EXISTS (
    SELECT 1 FROM public.leads l
     WHERE l.id = p_lead_id
       AND (
         l.assigned_to_user_id = v_user_id
         OR EXISTS (
           SELECT 1 FROM public.lead_shares ls
            WHERE ls.lead_id = l.id AND ls.recipient_user_id = v_user_id
         )
       )
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    t.id,
    t.event_type::text,
    t.actor_user_id,
    t.actor_role,
    u.email_or_username AS actor_name,
    t.payload,
    t.occurred_at
  FROM public.lead_timeline t
  LEFT JOIN public.users u ON u.id = t.actor_user_id
  WHERE t.lead_id = p_lead_id
  ORDER BY t.occurred_at DESC
  LIMIT 200;
END;
$$;

COMMENT ON FUNCTION public.get_lead_timeline(uuid) IS
  'Story 4.4 (patched P5) — Returns timeline for one lead. Caller must be owner OR active share recipient (AC-5 fix). SECURITY DEFINER; silently returns 0 rows if not accessible.';

REVOKE EXECUTE ON FUNCTION public.get_lead_timeline(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_lead_timeline(uuid) TO authenticated;
