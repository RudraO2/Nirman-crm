-- 0058_tier_aware_assignment.sql
-- Story 12.2 (Epic 12) — FR-39/FR-41. Tier-aware lead-assignment targets.
--
-- Leaders/partners/receptionists stay role='employee' (so the 17 hardened RPCs keep working
-- unchanged), but they must NOT be valid LEAD-ASSIGNMENT TARGETS — only front_line_rep owns
-- leads (arch §13.4). This re-creates the two functions whose "is-employee" check actually
-- meant "is an individual-contributor rep" (see 12-2-predicate-audit.md). Every other `role`
-- guard in the codebase is is-admin / is-not-admin and is intentionally untouched.
--
-- Bodies reproduced from their latest definition (0054_harden_admin_role_guards.sql); ONLY the
-- target filter / returned-set filter changed. No signature/grant/search_path drift.
-- The target filter reads public.users.role_tier (DB column), so it is correct independent of
-- the JWT-claim stamping window (12.3). assign_lead already takes FOR UPDATE on the lead row
-- (AC: reclaim-vs-reassign lock) — preserved verbatim.
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

BEGIN;

-- 1. assign_lead — target must be an active front_line_rep ----------------------
CREATE OR REPLACE FUNCTION public.assign_lead(p_lead_id uuid, p_target_user_id uuid, p_deadline timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
  IF v_actor_role IS DISTINCT FROM 'admin' THEN
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

  SELECT id, role, role_tier, is_active, email_or_username
    INTO v_target
    FROM public.users
   WHERE id = p_target_user_id AND tenant_id = v_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'target_not_found' USING ERRCODE = 'P0002';
  END IF;
  -- CHANGED (12.2): target must be an active front_line_rep. Leaders/partners/receptionists
  -- are role='employee' but are NOT assignable lead owners.
  IF v_target.role <> 'employee'
     OR v_target.role_tier IS DISTINCT FROM 'front_line_rep'::public.role_tier
     OR v_target.is_active = false THEN
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
$function$;

-- 2. list_employees_for_assignment — return only front_line_rep candidates ------
CREATE OR REPLACE FUNCTION public.list_employees_for_assignment()
 RETURNS TABLE(id uuid, username text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
BEGIN
  IF v_actor_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT u.id, u.email_or_username
    FROM public.users u
   WHERE u.tenant_id = v_tenant_id
     AND u.role      = 'employee'
     AND u.role_tier = 'front_line_rep'::public.role_tier   -- CHANGED (12.2): reps only
     AND u.is_active = true
   ORDER BY u.email_or_username ASC;
END;
$function$;

COMMIT;
