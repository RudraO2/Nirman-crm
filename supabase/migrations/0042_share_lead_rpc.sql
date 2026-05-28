-- Story 4.4 — Employee shares a Lead with another Employee.
-- Adds: RLS INSERT + DELETE policies on lead_shares,
--        share_lead RPC, revoke_share RPC,
--        list_employees_for_share RPC (employee-accessible),
--        get_my_leads updated (is_shared column + shared-lead UNION).
-- Roll-forward only. Never edit after apply.

-- ── 1. RLS INSERT policy on lead_shares ─────────────────────────────────────
-- Belt-and-suspenders: share_lead (SECURITY DEFINER) handles all validation.
-- Policy guards direct table access: caller must own the lead.
CREATE POLICY lead_shares_owner_insert ON public.lead_shares
  FOR INSERT TO authenticated
  WITH CHECK (
    tenant_id = public.auth_tenant_id()
    AND EXISTS (
      SELECT 1 FROM public.leads l
       WHERE l.id                 = lead_id
         AND l.tenant_id          = public.auth_tenant_id()
         AND l.assigned_to_user_id = auth.uid()
    )
  );

-- ── 2. RLS DELETE policy on lead_shares ─────────────────────────────────────
-- Owner (granted_by_user_id) or admin may delete.
CREATE POLICY lead_shares_owner_delete ON public.lead_shares
  FOR DELETE TO authenticated
  USING (
    granted_by_user_id = auth.uid()
    OR (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin'
  );

-- ── 3. share_lead(p_lead_id, p_recipient_user_id) ───────────────────────────
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

  -- Lead must belong to caller's tenant and caller must be the owner
  IF NOT EXISTS (
    SELECT 1 FROM public.leads
     WHERE id                  = p_lead_id
       AND tenant_id           = v_tenant_id
       AND assigned_to_user_id = v_actor_id
  ) THEN
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

  -- Only log timeline when a new share row was actually inserted (idempotent)
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
  'Story 4.4 — Employee-only. Shares a lead with another active employee in same tenant. Idempotent (ON CONFLICT DO NOTHING). Logs shared timeline event only on first insert.';

REVOKE EXECUTE ON FUNCTION public.share_lead(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.share_lead(uuid, uuid) TO authenticated;

-- ── 4. revoke_share(p_lead_id, p_recipient_user_id) ─────────────────────────
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

  DELETE FROM public.lead_shares
   WHERE lead_id           = p_lead_id
     AND recipient_user_id = p_recipient_user_id;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  -- Log timeline only when a row was actually deleted (idempotent no-op otherwise)
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
  'Story 4.4 — Employee (owner) or admin. Revokes a lead share. Idempotent — no-op if row absent. Logs share_revoked timeline event only when row was actually deleted.';

REVOKE EXECUTE ON FUNCTION public.revoke_share(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.revoke_share(uuid, uuid) TO authenticated;

-- ── 5. list_employees_for_share — employee-accessible employee list ──────────
-- Distinct from list_employees_for_assignment (admin-only).
-- Returns active employees in caller's tenant for the share picker.
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
   ORDER BY u.email_or_username ASC;
END;
$$;

COMMENT ON FUNCTION public.list_employees_for_share() IS
  'Story 4.4 — Employee or admin. Returns all active employees in caller''s tenant for the share picker. Caller filters out self client-side.';

REVOKE EXECUTE ON FUNCTION public.list_employees_for_share() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.list_employees_for_share() TO authenticated;

-- ── 6. get_my_leads — add is_shared + shared-lead UNION ─────────────────────
-- Must DROP first: CREATE OR REPLACE cannot change RETURNS TABLE columns.
DROP FUNCTION IF EXISTS public.get_my_leads(int, int);

CREATE OR REPLACE FUNCTION public.get_my_leads(
  p_limit  int DEFAULT 100,
  p_offset int DEFAULT 0
)
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
  WITH all_leads AS (
    -- Owned leads (is_shared = false)
    SELECT
      l.id,
      l.status::text                                                        AS status,
      CASE WHEN l.name_encrypted IS NOT NULL
           THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
           ELSE NULL END                                                    AS name,
      extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key)             AS phone,
      l.source::text                                                        AS source,
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
      false                                                                 AS is_shared
    FROM public.leads l
    WHERE l.assigned_to_user_id = v_user_id
      AND l.status NOT IN ('dead', 'sold', 'future')

    UNION ALL

    -- Shared leads: recipient = caller, caller is not the owner
    SELECT
      l.id,
      l.status::text                                                        AS status,
      CASE WHEN l.name_encrypted IS NOT NULL
           THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
           ELSE NULL END                                                    AS name,
      extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key)             AS phone,
      l.source::text                                                        AS source,
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
      true                                                                  AS is_shared
    FROM public.leads l
    JOIN public.lead_shares ls
      ON ls.lead_id = l.id AND ls.recipient_user_id = v_user_id
    WHERE l.status NOT IN ('dead', 'sold', 'future')
      AND l.assigned_to_user_id <> v_user_id
  ),
  scored AS (
    SELECT
      a.id, a.status, a.name, a.phone, a.source, a.property_type, a.location,
      a.budget_min, a.budget_max, a.ticket_size, a.visit_date, a.next_followup_at,
      a.is_incomplete, a.pending_outcome_at, a.last_action_at, a.created_at, a.is_shared,
      CASE
        WHEN a.pending_outcome_at IS NOT NULL                                   THEN 1000
        WHEN a.status = 'hot'  AND a.next_followup_at IS NOT NULL
             AND a.next_followup_at < now()                                     THEN  700
        WHEN a.status = 'hot'  AND a.next_followup_at IS NOT NULL
             AND a.next_followup_at::date = current_date                        THEN  600
        WHEN a.status = 'hot'                                                   THEN  500
        WHEN a.status = 'warm' AND a.next_followup_at IS NOT NULL
             AND a.next_followup_at < now()                                     THEN  400
        WHEN a.status = 'warm'                                                  THEN  300
        WHEN a.status = 'cold' AND a.next_followup_at IS NOT NULL
             AND a.next_followup_at < now()                                     THEN  250
        WHEN a.status = 'cold'                                                  THEN  200
        WHEN a.last_action_at < now() - interval '7 days'                      THEN   50
        ELSE 100
      END::int                                                             AS urgency_score
    FROM all_leads a
  )
  SELECT
    s.id, s.status, s.name, s.phone, s.source, s.property_type, s.location,
    s.budget_min, s.budget_max, s.ticket_size, s.visit_date, s.next_followup_at,
    s.is_incomplete, s.pending_outcome_at, s.last_action_at, s.created_at,
    s.urgency_score, s.is_shared
  FROM scored s
  ORDER BY s.urgency_score DESC, s.last_action_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION public.get_my_leads(int, int) IS
  'Story 4.4 (updated) — Returns urgency-sorted active leads for auth.uid(): owned leads (is_shared=false) UNION ALL leads shared with caller (is_shared=true). Decrypts PII via vault. Excludes dead/sold/future.';

REVOKE EXECUTE ON FUNCTION public.get_my_leads(int, int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_leads(int, int) TO authenticated;
