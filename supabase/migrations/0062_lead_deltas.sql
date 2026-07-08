-- 0062_lead_deltas.sql
-- Story 13.1 (Epic 13 — Lead Registration v2) — FR-42/43/44/46/47.
--
-- ADDITIVE columns on leads + two new lead_source values. All new columns nullable/defaulted
-- so existing rows are untouched. secondary_phone_hash is stored but is NOT a duplicate-block
-- trigger (A-11). lock_started_at anchors the 90-day agent-lock (populated/backfilled in 13.5).
--
-- Source enum ADD VALUEs are BARE statements before the txn block — a new enum label must be
-- committed before use; nothing in this migration uses them, so it is safe. Enum values are
-- irreversible — list locked at 6 (walk_in, referral, associate, ad, cold_call, employee_referral).
--
-- File-based migration, applied via `supabase db push --linked`. Never MCP apply.

ALTER TYPE public.lead_source ADD VALUE IF NOT EXISTS 'cold_call';
ALTER TYPE public.lead_source ADD VALUE IF NOT EXISTS 'employee_referral';

BEGIN;

ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS secondary_phone_encrypted bytea,
  ADD COLUMN IF NOT EXISTS secondary_phone_hash      text,
  ADD COLUMN IF NOT EXISTS customer_code             text,
  ADD COLUMN IF NOT EXISTS visit_count               int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS source_agency_id          uuid REFERENCES public.agencies(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS lock_started_at           timestamptz;

COMMENT ON COLUMN public.leads.secondary_phone_encrypted IS
  'Story 13.1 — backup contact, pgp_sym_encrypt with vault lead_pii_key (same as primary). Mandatory for Complete (FR-42).';
COMMENT ON COLUMN public.leads.secondary_phone_hash IS
  'Story 13.1 — sha256(normalize_phone(secondary)). Stored for future use; NOT a dedup-block trigger (A-11).';
COMMENT ON COLUMN public.leads.customer_code IS
  'Story 13.1 — per-tenant unique human-readable code (e.g. NIR-7F3K). Delivered via WhatsApp/in-app (free); presented at reception to verify a visit (FR-44).';
COMMENT ON COLUMN public.leads.visit_count IS
  'Story 13.1 — number of verified/logged physical visits (FR-46). Drives funnel Visited stage (13.7).';
COMMENT ON COLUMN public.leads.source_agency_id IS
  'Story 13.1 — set when a partner_agency user sources the lead; scopes partner visibility (FR-40). NULL for internal leads.';
COMMENT ON COLUMN public.leads.lock_started_at IS
  'Story 13.1/13.5 — anchor for the 90-day agent-lock dedup (FR-47). Backfilled to now() at the 13.5 migration (NOT created_at).';

-- Per-tenant unique customer code (only when set).
CREATE UNIQUE INDEX IF NOT EXISTS leads_tenant_customer_code_idx
  ON public.leads (tenant_id, customer_code)
  WHERE customer_code IS NOT NULL;

-- FK index for partner scoping.
CREATE INDEX IF NOT EXISTS leads_source_agency_idx
  ON public.leads (source_agency_id)
  WHERE source_agency_id IS NOT NULL;

COMMIT;
