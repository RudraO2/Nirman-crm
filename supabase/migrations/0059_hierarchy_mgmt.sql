-- 0059_hierarchy_mgmt.sql
-- Story 12.4 (Epic 12) — FR-39. Builder Head manages the reporting hierarchy.
--
-- Adds set_user_hierarchy() to set a user's tier + reporting line with validation:
--   reports_to must be a strictly higher tier (same tenant); cycles rejected;
--   partner_agency requires an agency (and is_external=true); off-ladder tiers
--   (partner_agency, receptionist) have no reports_to. Audited to user_events.
--
-- The leader-with-reports deactivation block lives in the manage-employee edge fn
-- (it owns deactivation) — this migration provides nothing extra for that; the fn
-- queries reports_to_user_id directly.
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

-- New audit event value. Bare ADD VALUE (idempotent) BEFORE the txn block — a new
-- enum label must be committed before it can be used; CREATE FUNCTION only stores the
-- literal so it is safe, but keep it outside the explicit BEGIN to avoid any
-- "unsafe use of new value" edge on older planners.
ALTER TYPE public.user_event_type ADD VALUE IF NOT EXISTS 'hierarchy_changed';

BEGIN;

-- Rank for "strictly higher tier" checks. Off-ladder tiers (partner/receptionist) = 0.
CREATE OR REPLACE FUNCTION public.role_tier_rank(p_tier public.role_tier)
RETURNS int
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE p_tier
    WHEN 'super_admin'     THEN 4
    WHEN 'builder_head'    THEN 3
    WHEN 'team_leader'     THEN 2
    WHEN 'front_line_rep'  THEN 1
    ELSE 0  -- partner_agency, receptionist: off the sales ladder
  END
$$;

COMMENT ON FUNCTION public.role_tier_rank(public.role_tier) IS
  'Story 12.4 — ordinal for tier hierarchy checks. super>head>leader>rep; partner/receptionist off-ladder (0).';

CREATE OR REPLACE FUNCTION public.set_user_hierarchy(
  p_user_id     uuid,
  p_role_tier   public.role_tier,
  p_reports_to  uuid DEFAULT NULL,
  p_agency_id   uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor_id   uuid := auth.uid();
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
  v_target     RECORD;
  v_parent     RECORD;
  v_is_external boolean;
  v_agency_id  uuid;
  v_creates_cycle boolean;
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

  SELECT id, role, role_tier INTO v_target
    FROM public.users
   WHERE id = p_user_id AND tenant_id = v_tenant_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- Agency / external rules
  IF p_role_tier = 'partner_agency' THEN
    IF p_agency_id IS NULL THEN
      RAISE EXCEPTION 'agency_required_for_partner' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.agencies WHERE id = p_agency_id AND tenant_id = v_tenant_id) THEN
      RAISE EXCEPTION 'agency_not_found' USING ERRCODE = 'P0002';
    END IF;
    v_is_external := true;
    v_agency_id   := p_agency_id;
  ELSE
    v_is_external := false;
    v_agency_id   := NULL;  -- clear any stale agency link
  END IF;

  -- Reporting line rules
  IF p_role_tier IN ('partner_agency', 'receptionist') THEN
    -- Off-ladder: no internal reporting line.
    IF p_reports_to IS NOT NULL THEN
      RAISE EXCEPTION 'off_ladder_tier_has_no_reports_to' USING ERRCODE = '22023';
    END IF;
  ELSIF p_reports_to IS NOT NULL THEN
    IF p_reports_to = p_user_id THEN
      RAISE EXCEPTION 'cannot_report_to_self' USING ERRCODE = '22023';
    END IF;
    SELECT id, role_tier INTO v_parent
      FROM public.users
     WHERE id = p_reports_to AND tenant_id = v_tenant_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'reports_to_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF public.role_tier_rank(v_parent.role_tier) <= public.role_tier_rank(p_role_tier) THEN
      RAISE EXCEPTION 'reports_to_must_be_higher_tier' USING ERRCODE = '22023';
    END IF;
    -- Cycle: reject if p_user_id is an ANCESTOR of p_reports_to (would close a loop).
    WITH RECURSIVE up AS (
      SELECT u.id, u.reports_to_user_id
        FROM public.users u
       WHERE u.id = p_reports_to
      UNION ALL
      SELECT u2.id, u2.reports_to_user_id
        FROM public.users u2
        JOIN up ON u2.id = up.reports_to_user_id
    )
    SELECT EXISTS (SELECT 1 FROM up WHERE id = p_user_id) INTO v_creates_cycle;
    IF v_creates_cycle THEN
      RAISE EXCEPTION 'reporting_cycle_detected' USING ERRCODE = '22023';
    END IF;
  END IF;

  UPDATE public.users
     SET role_tier          = p_role_tier,
         reports_to_user_id = CASE WHEN p_role_tier IN ('partner_agency','receptionist') THEN NULL ELSE p_reports_to END,
         agency_id          = v_agency_id,
         is_external        = v_is_external
   WHERE id = p_user_id AND tenant_id = v_tenant_id;

  INSERT INTO public.user_events (tenant_id, user_id, actor_id, event_type, payload)
  VALUES (
    v_tenant_id, p_user_id, v_actor_id, 'hierarchy_changed',
    jsonb_build_object('role_tier', p_role_tier, 'reports_to', p_reports_to, 'agency_id', v_agency_id, 'is_external', v_is_external)
  );

  RETURN jsonb_build_object(
    'user_id', p_user_id, 'role_tier', p_role_tier,
    'reports_to', (CASE WHEN p_role_tier IN ('partner_agency','receptionist') THEN NULL ELSE p_reports_to END),
    'agency_id', v_agency_id, 'is_external', v_is_external
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.set_user_hierarchy(uuid, public.role_tier, uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_user_hierarchy(uuid, public.role_tier, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.set_user_hierarchy(uuid, public.role_tier, uuid, uuid) IS
  'Story 12.4 — admin-only. Sets a user tier + reporting line. reports_to must be strictly higher tier same tenant; cycles rejected; partner_agency requires agency (is_external=true); partner/receptionist have no reports_to. Audited to user_events.';

COMMIT;
