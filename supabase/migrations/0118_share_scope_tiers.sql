-- 0118_share_scope_tiers.sql
-- Found live on-device 2026-07-12 (Rudra, eyeball session): the Share sheet
-- offered the receptionist as a recipient — and code inspection + a live local
-- repro showed the real hole behind it.
--
-- Both share fns predate Epic 12's tiers (Story 4.4/0054/0055) and only check
-- role='employee', so:
--   1. list_employees_for_share offered EVERY active employee tenant-wide:
--      receptionists (who can never read leads — get_my_leads denies them, a
--      dead-end share) and, across the internal/external boundary, partner
--      users to internal reps and internal reps to partners.
--   2. share_lead accepted those recipients. Live repro: rep shares an internal
--      lead to a partner_agency user → partner's get_my_leads AND
--      get_lead_by_id return it, decrypted PII included — violating 12.6's
--      "partner sees only their own agency's leads (never internal leads)".
--
-- Fix, enforced server-side in BOTH fns (the list is UX, share_lead is law):
--   * receptionist is never an eligible recipient (gate-not-own, 0061);
--   * internal caller → internal recipients only;
--   * partner caller  → own-agency recipients only.
-- Tier/boundary read from public.users (authoritative), NOT the JWT — role_tier
-- may be absent from tokens (12.3 backfill note).
--
-- Bodies otherwise verbatim from 0054 (list) / 0055 (share).
-- File-based migration; never MCP apply.

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. list_employees_for_share — tier/boundary-scoped picker
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_employees_for_share()
 RETURNS TABLE(id uuid, username text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor_id   uuid := auth.uid();
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
  v_actor      RECORD;
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF COALESCE(v_actor_role, '') NOT IN ('employee', 'admin') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT u.is_external, u.agency_id INTO v_actor
    FROM public.users u
   WHERE u.id = v_actor_id AND u.tenant_id = v_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT u.id, u.email_or_username
    FROM public.users u
   WHERE u.tenant_id = v_tenant_id
     AND u.role      = 'employee'
     AND u.is_active = true
     AND u.id        <> v_actor_id
     -- 0118: receptionist can never read leads — never a share target
     AND COALESCE(u.role_tier::text, '') <> 'receptionist'
     -- 0118: internal↔external boundary — partner shares within own agency,
     -- internal users share internally
     AND CASE WHEN COALESCE(v_actor.is_external, false)
              THEN u.agency_id IS NOT DISTINCT FROM v_actor.agency_id
              ELSE COALESCE(u.is_external, false) = false
         END
   ORDER BY u.email_or_username ASC;
END;
$function$;

COMMENT ON FUNCTION public.list_employees_for_share() IS
  'Story 4.4 + 0118 — share-recipient picker. Excludes receptionists (gate-not-own) and enforces the internal/external boundary: internal callers see internal employees, partner callers see own-agency members only. Mirrors share_lead''s server-side rule.';

-- ────────────────────────────────────────────────────────────────────────────
-- 2. share_lead — enforce the same rule at the write
-- ────────────────────────────────────────────────────────────────────────────
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
  v_actor      RECORD;
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

  SELECT u.id, u.role, u.is_active, u.email_or_username,
         u.role_tier, u.is_external, u.agency_id
    INTO v_recipient
    FROM public.users u
   WHERE u.id = p_recipient_user_id AND u.tenant_id = v_tenant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'recipient_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_recipient.role <> 'employee' OR v_recipient.is_active = false THEN
    RAISE EXCEPTION 'recipient_not_eligible' USING ERRCODE = '22023';
  END IF;

  -- 0118: receptionist can never read leads — a share to them is a dead end.
  IF COALESCE(v_recipient.role_tier::text, '') = 'receptionist' THEN
    RAISE EXCEPTION 'recipient_not_eligible' USING ERRCODE = '22023';
  END IF;

  -- 0118: internal/external boundary (12.6 — partner never sees internal
  -- leads, internal team never leaks into an agency's book via share).
  SELECT u.is_external, u.agency_id INTO v_actor
    FROM public.users u
   WHERE u.id = v_actor_id AND u.tenant_id = v_tenant_id;
  IF COALESCE(v_actor.is_external, false) THEN
    IF v_recipient.agency_id IS DISTINCT FROM v_actor.agency_id THEN
      RAISE EXCEPTION 'recipient_not_eligible' USING ERRCODE = '22023';
    END IF;
  ELSE
    IF COALESCE(v_recipient.is_external, false) THEN
      RAISE EXCEPTION 'recipient_not_eligible' USING ERRCODE = '22023';
    END IF;
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
  'Story 4.4 (P1; 8.1) + 0118 — Employee-only, owner-only share. 0118 adds tier scoping: receptionists are never eligible recipients, and shares cannot cross the internal/external boundary (partner → own agency only). FOR UPDATE lock vs assign_lead cascade-revoke; idempotent.';

COMMIT;
