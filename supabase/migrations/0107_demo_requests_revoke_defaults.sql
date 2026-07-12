-- 0107_demo_requests_revoke_defaults.sql
-- Belt-and-braces follow-up to 0103 (audit H10), found while pinning the audit
-- fixes in pgTAP: demo_requests was created AFTER the 0098/0099 hardening sweep
-- and inherited Supabase's broad default privileges — anon/authenticated held
-- table-level SELECT/UPDATE/DELETE grants. NOT exploitable (FORCE RLS + the only
-- policy is INSERT, so every read/write-back returns zero rows), but the 0098/
-- 0099 house style is grants-match-intent: write-only means write-only at the
-- GRANT layer too. Keeps the column-scoped INSERT (email, source) from 0103.
-- File-based migration; never MCP apply.

BEGIN;

REVOKE SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.demo_requests FROM anon, authenticated;

COMMIT;
