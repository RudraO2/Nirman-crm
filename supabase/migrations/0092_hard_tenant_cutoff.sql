-- 0092_hard_tenant_cutoff.sql
-- Story 9.6 (Epic 9) — make the prepaid lockout a REAL, un-bypassable cutoff for
-- EVERYONE (admins already gated; this closes the employee hole), and let any
-- tenant member read their own billing status so the app can show the recharge
-- screen + the 3-day advance warning instead of raw errors.
--
-- WHY: a code review found `get_my_leads` (latest def 0061) is SECURITY DEFINER
-- and filters only on `assigned_to_user_id = auth.uid()` — it never consulted the
-- `auth_tenant_id()` chokepoint (0056), so a SUSPENDED tenant's employees kept
-- reading their leads (access not actually cut) and the app's employee-lockout
-- detection never fired. An audit of every employee-callable RPC the mobile app
-- uses found `get_my_leads` is the ONLY one missing the chokepoint; all others
-- (get_lead_by_id, get_my_archived_leads, set_followup, share_lead, call fns, …)
-- already gate on auth_tenant_id(). So this migration only has to fix that one.
--
-- Two changes, both additive/idempotent (CREATE OR REPLACE), no schema/data change:
--   1. get_my_leads: add the tenant-status chokepoint guard. Suspended/cancelled
--      → auth_tenant_id() is NULL (0056 filters status IN trial,active) → raise the
--      same `missing_tenant_context` (P0001) the rest of the data layer raises, so
--      the client shows the recharge screen and NO lead data is returned. Active/
--      trial tenants: auth_tenant_id() is non-null → guard is a no-op (unaffected).
--   2. get_my_billing_status: relax from admin-only to ANY authenticated tenant
--      member (still own-tenant only, still NO ledger) so employees can detect
--      lockout and see the advance-expiry warning — same {status,plan_name,
--      paid_until,days_remaining} shape. Still deliberately bypasses the chokepoint
--      so a suspended tenant is readable (that is exactly when the screen shows).
--
-- Prod head is 0091. This is 0092. File-based, `supabase db push --linked`. NEVER MCP apply.

BEGIN;

-- 1. get_my_leads — reproduced verbatim from 0061 with ONLY the tenant-cutoff guard added. -------
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

  -- Story 9.6: HARD tenant cutoff. A suspended/cancelled (or lapsed) tenant resolves
  -- to a NULL auth_tenant_id() (0056 chokepoint: status IN trial,active only), so deny
  -- data with the standard `missing_tenant_context` signal — the app routes to the
  -- recharge screen instead of showing an error, and no lead data is reachable.
  -- Active/trial tenants: auth_tenant_id() is non-null → this is a no-op.
  IF public.auth_tenant_id() IS NULL THEN
    RAISE EXCEPTION 'missing_tenant_context' USING ERRCODE = 'P0001';
  END IF;

  -- Story 12.6: receptionist is a gate-only role (verifies visits, owns no leads).
  -- Deny outright — defense-in-depth beyond ownership gating.
  IF public.auth_role_tier() = 'receptionist' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
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
  'Story 4.4 + 12.6 + 9.6 — urgency-sorted active leads for auth.uid(): owned UNION ALL shared. Decrypts PII via vault. Excludes dead/sold/future. Receptionist denied. Story 9.6: now fail-closed on tenant status via auth_tenant_id() (suspended tenant -> missing_tenant_context, no data).';

REVOKE EXECUTE ON FUNCTION public.get_my_leads(int, int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_leads(int, int) TO authenticated;

-- 2. get_my_billing_status — relax to any authenticated tenant member (was admin-only). ---------
CREATE OR REPLACE FUNCTION public.get_my_billing_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tenant_id uuid;
  v_row       RECORD;
BEGIN
  -- Story 9.6: readable by ANY authenticated tenant member (admin OR employee) so both
  -- the recharge lockout screen AND the advance-expiry warning work for everyone. Still
  -- own-tenant only, still NO ledger exposed. GRANT is authenticated-only (no anon).

  -- UUID-guarded JWT tenant extraction (verbatim from auth_tenant_id 0056), WITHOUT the
  -- status filter, so a suspended tenant's member still gets an answer (that is when the
  -- recharge screen shows).
  v_tenant_id := (
    CASE
      WHEN (auth.jwt() -> 'app_metadata') ->> 'tenant_id'
             ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      THEN ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid
      ELSE NULL
    END
  );
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'tenant_missing' USING ERRCODE = '42501';
  END IF;

  SELECT t.status, p.name AS plan_name, t.paid_until,
         CASE WHEN t.paid_until IS NULL THEN NULL
              ELSE ceil(extract(epoch FROM (t.paid_until - now())) / 86400.0)::int
         END AS days_remaining
    INTO v_row
    FROM public.tenants t
    LEFT JOIN public.plans p ON p.id = t.plan_id
   WHERE t.id = v_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tenant_missing' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'status',         v_row.status,
    'plan_name',      v_row.plan_name,
    'paid_until',     v_row.paid_until,
    'days_remaining', v_row.days_remaining
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_billing_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_billing_status() TO authenticated, service_role;

COMMENT ON FUNCTION public.get_my_billing_status() IS
  'Story 9.1 + 9.6 — own-tenant billing read for the recharge screen + advance-expiry warning. Returns {status,plan_name,paid_until,days_remaining}. Story 9.6: relaxed from admin-only to ANY authenticated tenant member (own-tenant only, no ledger). Deliberately bypasses auth_tenant_id() so a SUSPENDED tenant is still readable.';

COMMIT;
