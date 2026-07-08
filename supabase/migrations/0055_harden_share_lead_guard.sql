-- 0055_harden_share_lead_guard.sql
-- Story 8.1 (Epic 8) follow-up — code-review finding (Edge Case Hunter).
--
-- share_lead was the one role-guarded SECURITY DEFINER function NOT covered by
-- migration 0054 (which scoped to admin-only fns). It carries the identical
-- NULL-permissive scalar guard:
--   v_actor_role <> 'employee'   -- NULL <> 'employee' => NULL => IF skipped => ALLOWED
-- Same SQL three-valued-logic bypass class 0054 fixed. Today every authenticated
-- user carries a stamped role, so latent; Story 8.3 (public self-serve sign-up)
-- creates a momentarily role-less auth.users row, making it reachable.
-- Downstream ownership check (assigned_to_user_id = v_actor_id) already prevents
-- cross-tenant abuse, but the deny-guard itself must be NULL-safe for consistency
-- with the security gate.
--
-- Fix: scalar guard uses NULL-safe `IS DISTINCT FROM 'employee'`.
-- Body otherwise byte-for-byte identical to the current definition (0044), grants
-- preserved (CREATE OR REPLACE keeps them; re-issued below to match 0044).

BEGIN;

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
  IF v_actor_role IS DISTINCT FROM 'employee' THEN
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
  'Story 4.4 (patched P1; 8.1 guard hardened) — Employee-only. NULL-safe role guard (IS DISTINCT FROM). FOR UPDATE lock on leads row prevents race with assign_lead cascade-revoke. Idempotent (ON CONFLICT DO NOTHING). Logs shared timeline only on first insert.';

REVOKE EXECUTE ON FUNCTION public.share_lead(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.share_lead(uuid, uuid) TO authenticated;

COMMIT;
