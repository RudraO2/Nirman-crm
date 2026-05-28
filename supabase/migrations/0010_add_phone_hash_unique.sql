-- Story 2.1 (review patch) — Enforce per-tenant phone uniqueness
-- FR-3 (duplicate phone prevention): DB-level guarantee replacing advisory SELECT+INSERT
-- Code review finding: D1 — concurrent Edge Function calls could bypass the application-layer
-- duplicate check; UNIQUE constraint ensures the DB rejects duplicates atomically.
--
-- Roll-forward only. Never edit after apply.

ALTER TABLE public.leads
  ADD CONSTRAINT leads_tenant_phone_hash_unique UNIQUE (tenant_id, phone_hash);

COMMENT ON CONSTRAINT leads_tenant_phone_hash_unique ON public.leads IS
  'Story 2.1 review — Per-tenant phone uniqueness (FR-3). Edge Function catches unique_violation and returns duplicate_lead error code.';
