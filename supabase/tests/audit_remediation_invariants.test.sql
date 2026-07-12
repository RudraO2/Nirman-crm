-- Robustness-audit (2026-07-11) remediation invariants — durable regression guardrails.
-- Run via: supabase test db (pgTAP). Asserts the shape of every DB-level audit fix
-- (0097–0106) so a future migration can't silently regress one. Behavioral proof was
-- done live at fix time; these keep the guarantees pinned.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(16);

-- ── C1 (0097): usernames globally unique — login is a global lookup ──────────
SELECT ok(
  EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
          AND indexname='users_email_or_username_global_key'),
  '0097: global unique username index present (C1 + provision TOCTOU backstop)');

-- ── C2 (0098): leads direct client access locked to a 3-column SELECT ────────
SELECT ok(NOT has_table_privilege('authenticated','public.leads','UPDATE'),
  '0098: authenticated cannot UPDATE leads directly');
SELECT ok(NOT has_table_privilege('authenticated','public.leads','DELETE'),
  '0098: authenticated cannot DELETE leads directly');
SELECT ok(NOT has_column_privilege('authenticated','public.leads','phone_hash','SELECT'),
  '0098/H4: phone_hash not readable by clients (brute-force surface closed)');

-- ── C3/H3 (0099): units writes RPC-only; margin column never client-readable ─
SELECT ok(NOT has_table_privilege('authenticated','public.units','UPDATE'),
  '0099: authenticated cannot UPDATE units directly (hold→confirm protocol not bypassable)');
SELECT ok(NOT has_column_privilege('authenticated','public.units','cost_paise','SELECT'),
  '0099: cost_paise (margin) not column-granted to authenticated');

-- ── C4 (0099): unit_holds SELECT-only ────────────────────────────────────────
SELECT ok(
  NOT has_table_privilege('authenticated','public.unit_holds','INSERT')
  AND NOT has_table_privilege('authenticated','public.unit_holds','UPDATE')
  AND NOT has_table_privilege('authenticated','public.unit_holds','DELETE'),
  '0099: holds cannot be forged/resurrected/deleted outside hold_unit');

-- ── H2 (0099): amendments fully RPC-only ─────────────────────────────────────
SELECT ok(NOT has_table_privilege('authenticated','public.amendments','SELECT'),
  '0099: amendments have no direct client access at all');

-- ── H1 (0100): platform-admin gate demands aal2 once TOTP exists ─────────────
SELECT ok(
  (SELECT prosrc LIKE '%aal%' FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='is_platform_admin'),
  '0100: is_platform_admin checks JWT aal (MFA server enforcement)');

-- ── H5/M17 (0101): confirm_booking scoped + expiry-checked ───────────────────
SELECT ok(
  (SELECT prosrc LIKE '%visible_user_ids%' AND prosrc LIKE '%expires_at%' FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='confirm_booking'),
  '0101: confirm_booking has team_leader subtree scope + rejects lapsed holds');

-- ── H6 (0102): renew_tenant idempotency window ───────────────────────────────
SELECT ok(
  (SELECT prosrc LIKE '%deduplicated%' FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='renew_tenant'),
  '0102: renew_tenant dedupes identical payments (double-click safe)');

-- ── M18 (0104): force_release reconciles hold row + booked lead ──────────────
SELECT ok(
  (SELECT prosrc LIKE '%booking_reverted%' AND prosrc LIKE '%hold_cancelled%' FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='change_unit_inventory_state'),
  '0104: force_release reverts the booked lead + logs hold_cancelled/booking_reverted');
SELECT set_has(
  $$SELECT e.enumlabel::text FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
    WHERE t.typname='timeline_event_type'$$,
  $$VALUES ('booking_reverted'), ('hold_cancelled')$$,
  '0104: timeline_event_type carries the two reconciliation labels');

-- ── L3 (0105): get_active_holds exposes the load-time CAS token ──────────────
SELECT ok(
  (SELECT pg_get_function_result(oid) LIKE '%unit_status_version%' FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='get_active_holds'),
  '0105: get_active_holds returns unit_status_version for force-release CAS');

-- ── L5 (0106): bare reactivate rejected for cancelled tenants ────────────────
SELECT ok(
  (SELECT prosrc LIKE '%tenant_cancelled_use_renew%' FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='ops_reactivate_tenant'),
  '0106: ops_reactivate_tenant rejects cancelled tenants (renew is the revival path)');

-- ── H10 (0103): demo_requests — anon may INSERT (column-granted email/source
--    only, so table-level INSERT is intentionally false) and never SELECT ────
SELECT ok(
  has_column_privilege('anon','public.demo_requests','email','INSERT')
  AND NOT has_table_privilege('anon','public.demo_requests','SELECT'),
  '0103: marketing demo form can write but never read demo_requests');

SELECT * FROM finish();
ROLLBACK;
