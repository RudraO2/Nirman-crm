-- 0097_global_username_uniqueness.sql
-- Robustness audit 2026-07-11, finding C1 (login hard-coded to seed tenant).
--
-- The login edge fn now looks up public.users by email_or_username GLOBALLY
-- (the SEED_TENANT_ID filter is removed — it broke login for every tenant
-- provisioned after V1). That lookup is only sound if a username can never
-- exist in two tenants at once. Both creation paths already guarantee this:
--   * create-employee goes through GoTrue createUser (auth.users.email is
--     globally unique),
--   * provision_tenant (0091) explicitly checks BOTH stores globally.
-- This index makes the invariant a DB constraint instead of a convention,
-- so a future creation path cannot silently break login again.
--
-- The per-tenant unique index from 0001 (tenant_id, lower(email_or_username))
-- is left in place; this one strictly implies it but dropping it is not worth
-- the churn.

BEGIN;

-- Normalize any legacy mixed-case rows so the login fn can use an exact eq()
-- lookup (ilike was wildcard-injectable: PostgREST maps * to % and the input
-- is user-controlled). Both creation paths already lowercase on write; this
-- is a one-time sweep for anything older. Safe within a tenant: 0001's
-- (tenant_id, lower(email_or_username)) unique index already forbids
-- case-only duplicates.
UPDATE public.users
   SET email_or_username = lower(email_or_username)
 WHERE email_or_username <> lower(email_or_username);

CREATE UNIQUE INDEX IF NOT EXISTS users_email_or_username_global_key
  ON public.users (lower(email_or_username));

COMMENT ON INDEX public.users_email_or_username_global_key IS
  'C1 fix: login looks up usernames globally (no tenant filter) — usernames must be globally unique across tenants.';

COMMIT;
