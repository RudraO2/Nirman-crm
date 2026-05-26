-- Story 1.1 — Initialize multi-tenant schema with row-level security
-- FRs/NFRs satisfied: NFR-11 (tenant_id on every table), NFR-12 (query-layer tenant scoping),
--                    NFR-13 (auth tokens carry tenant_id claim — consumed here via app.current_tenant)
-- Architecture decisions: 1 (Postgres+Supabase), 2 (RLS isolation), 4 (Supabase Auth + JWT claims),
--                         5 (declarative SQL migrations), 14 (multi-tenancy day-1)
--
-- Roll-forward only. Never edit after apply.

-- ────────────────────────────────────────────────────────────────────────────
-- Extensions (pgcrypto provides gen_random_uuid; pgtap for test runner)
-- ────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ────────────────────────────────────────────────────────────────────────────
-- user_role enum
-- ────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    CREATE TYPE public.user_role AS ENUM ('admin', 'employee');
  END IF;
END
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- tenants
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tenants (
  id          uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  name        text NOT NULL,
  timezone    text NOT NULL DEFAULT 'Asia/Kolkata',
  created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.tenants IS
  'Story 1.1 — Tenant root. Every business-domain row hangs off tenant_id. timezone drives all date-bucketed queries.';

-- ────────────────────────────────────────────────────────────────────────────
-- users
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.users (
  id                     uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id              uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  role                   public.user_role NOT NULL,
  email_or_username      text NOT NULL,
  bcrypt_password_hash   text NOT NULL,
  must_change_password   boolean NOT NULL DEFAULT false,
  is_active              boolean NOT NULL DEFAULT true,
  created_at             timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.users IS
  'Story 1.1 — Application users (admin + employee). Distinct from auth.users; linkage to auth.uid() comes in Story 1.4.';

-- Unique login handle per tenant (case-insensitive)
CREATE UNIQUE INDEX IF NOT EXISTS users_tenant_login_uniq
  ON public.users (tenant_id, lower(email_or_username));

-- Index FK column (every FK indexed per arch §Database Patterns)
CREATE INDEX IF NOT EXISTS users_tenant_id_idx
  ON public.users (tenant_id);

-- ────────────────────────────────────────────────────────────────────────────
-- Row Level Security — enable + force on both tables
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenants FORCE  ROW LEVEL SECURITY;

ALTER TABLE public.users   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users   FORCE  ROW LEVEL SECURITY;

-- ────────────────────────────────────────────────────────────────────────────
-- Tenant isolation policies
--
-- NULLIF wrap on current_setting() makes the policy NULL-safe:
--   * setting absent → current_setting(..., true) returns '' (empty string)
--   * NULLIF('', '') → NULL
--   * NULL::uuid     → NULL
--   * tenant_id = NULL → NULL (treated as false) → row filtered out
-- This satisfies AC-8 ("zero rows when app.current_tenant unset").
-- ────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS tenants_self_visible ON public.tenants;
CREATE POLICY tenants_self_visible ON public.tenants
  FOR ALL
  TO authenticated
  USING      (id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
  WITH CHECK (id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

DROP POLICY IF EXISTS users_tenant_isolation ON public.users;
CREATE POLICY users_tenant_isolation ON public.users
  FOR ALL
  TO authenticated
  USING      (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
  WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

-- ────────────────────────────────────────────────────────────────────────────
-- Grants — authenticated needs CRUD; RLS gates row visibility
-- anon receives NO grants on these tables
-- service_role bypasses RLS implicitly via BYPASSRLS attribute
-- ────────────────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tenants TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.users   TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- set_current_tenant(uuid) — SECURITY DEFINER RPC
--
-- Edge Functions and the PostgREST pre-request hook (Story 1.4 wiring) call this
-- to bind app.current_tenant for the duration of the current transaction.
-- The third argument `true` on set_config makes the setting transaction-local
-- (equivalent to SET LOCAL), so it does not leak across pooled connections.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_current_tenant(tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM set_config('app.current_tenant', tenant_id::text, true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_current_tenant(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.set_current_tenant(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.set_current_tenant(uuid) IS
  'Story 1.1 — binds app.current_tenant GUC for current transaction. Edge Functions call this after JWT verify. Direct PostgREST callers can invoke via supabase.rpc(''set_current_tenant'', {tenant_id}) in a pre-request hook (Story 1.4).';
