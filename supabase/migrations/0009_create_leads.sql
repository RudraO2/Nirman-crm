-- Story 2.1 — Lead schema with normalized phone hash and encrypted PII
-- FRs: FR-1 (14-field lead form), FR-2 (Quick-Capture), FR-3 (duplicate phone prevention),
--      FR-4 (status-first entry), FR-16 (archiving), FR-18 (visibility isolation),
--      FR-19 (auto-Timeline), FR-21 (Future Pool interest_type)
-- NFRs: NFR-8 (PII encryption — columns created here; encrypt/decrypt in Edge Functions),
--       NFR-11, NFR-12 (multi-tenancy day-1), NFR-15 (no data loss on crash)
-- Architecture decisions: 1, 2, 3, 5, 22, 23
--
-- Roll-forward only. Never edit after apply.

-- ────────────────────────────────────────────────────────────────────────────
-- Extensions
-- ────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;

-- ────────────────────────────────────────────────────────────────────────────
-- Enums
-- ────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'lead_status') THEN
    CREATE TYPE public.lead_status AS ENUM (
      'warm', 'cold', 'hot', 'dead', 'sold', 'future'
    );
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'lead_source') THEN
    CREATE TYPE public.lead_source AS ENUM (
      'walk_in', 'referral', 'associate', 'ad'
    );
  END IF;
END
$$;

COMMENT ON TYPE public.lead_status IS
  'Story 2.1 — Lead pipeline stage. dead/sold/future trigger archiving (FR-16).';
COMMENT ON TYPE public.lead_source IS
  'Story 2.1 — How the lead was acquired. Maps to FR-1 Source field.';

-- ────────────────────────────────────────────────────────────────────────────
-- normalize_phone(text) — canonical 10-digit Indian mobile number
-- Strips: +91 / 0091 country prefix, leading 0, spaces, dashes, parens, dots
-- Returns NULL if result is not exactly 10 digits.
-- IMMUTABLE so it can be used in indexed expressions.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.normalize_phone(raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  cleaned text;
BEGIN
  IF raw IS NULL THEN
    RETURN NULL;
  END IF;
  -- Strip all non-digit characters
  cleaned := regexp_replace(raw, '[^\d]', '', 'g');
  -- Strip leading country code: 91 prefix on 12-digit string
  IF length(cleaned) = 12 AND left(cleaned, 2) = '91' THEN
    cleaned := right(cleaned, 10);
  END IF;
  -- Strip leading 0 on 11-digit string
  IF length(cleaned) = 11 AND left(cleaned, 1) = '0' THEN
    cleaned := right(cleaned, 10);
  END IF;
  -- Return 10-digit canonical form; NULL if unexpected length
  IF length(cleaned) = 10 THEN
    RETURN cleaned;
  END IF;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.normalize_phone(text) IS
  'Story 2.1 — Returns canonical 10-digit Indian mobile. Strips +91/0091/91 prefix, leading 0, spaces, dashes. Returns NULL if result ≠ 10 digits.';

-- ────────────────────────────────────────────────────────────────────────────
-- set_updated_at() trigger function
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_updated_at() IS
  'Story 2.1 — Generic BEFORE UPDATE trigger: sets updated_at = now(). Reusable across tables.';

-- ────────────────────────────────────────────────────────────────────────────
-- leads
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.leads (
  id                   uuid            PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id            uuid            NOT NULL REFERENCES public.tenants(id)  ON DELETE RESTRICT,
  assigned_to_user_id  uuid            REFERENCES  public.users(id)            ON DELETE SET NULL,

  -- Pipeline state
  status               public.lead_status NOT NULL DEFAULT 'cold',
  source               public.lead_source,

  -- PII — stored encrypted (pgp_sym_encrypt via Edge Function).
  -- Encryption key: vault secret 'lead_pii_key'.
  -- Decrypt via: pgp_sym_decrypt(col, key) in Edge Function only — never in client SQL.
  name_encrypted       bytea,
  phone_encrypted      bytea           NOT NULL,

  -- Indexed lookup columns (plaintext, non-sensitive)
  -- phone_hash: encode(sha256(normalize_phone(raw_phone)::bytea), 'hex') — computed in Edge Function
  phone_hash           text            NOT NULL,
  -- name_search: lower(name_plaintext) — arch Decision 22, admin-only pg_trgm search.
  -- Deliberate trade-off: plaintext for searchability, admin-gated endpoint.
  name_search          text,

  -- Lead form fields (FR-1)
  property_type        text,           -- Flat, Plot, Villa, Commercial, etc.
  location             text,
  budget_min           bigint,         -- stored in paise (₹1 = 100 paise)
  budget_max           bigint,
  ticket_size          text,           -- 2BHK, 3BHK, 4BHK, Penthouse
  remarks              text,
  visit_date           timestamptz,
  next_followup_at     timestamptz,

  -- Future Pool (FR-21): required at app-layer when status = 'future'
  -- No DB CHECK — enforced by Edge Function Zod (interest_type_required error code)
  interest_type        text,

  -- Status flags
  is_incomplete        boolean         NOT NULL DEFAULT true,
  pending_outcome_at   timestamptz,    -- set when call_initiated; cleared on any action (FR-8)

  -- Timestamps for urgency sort (FR-17) and activity tracking
  last_action_at       timestamptz     DEFAULT now(),
  reschedule_count     integer         NOT NULL DEFAULT 0,

  created_at           timestamptz     NOT NULL DEFAULT now(),
  updated_at           timestamptz     NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.leads IS
  'Story 2.1 — Core lead record. PII encrypted at column level (Edge Function); phone_hash enables duplicate detection without decryption.';
COMMENT ON COLUMN public.leads.phone_hash IS
  'SHA-256 hex of normalize_phone(raw). Computed in Edge Function before INSERT/UPDATE. Indexed for O(1) duplicate lookup.';
COMMENT ON COLUMN public.leads.name_search IS
  'Lowercase plaintext name for pg_trgm admin search (arch Decision 22). Deliberate trade-off: admin-only endpoint guards access.';
COMMENT ON COLUMN public.leads.budget_min IS
  'Budget lower bound stored in paise (₹1 = 100 paise). Display: ₹(budget_min / 100).toLocaleString(''en-IN'').';
COMMENT ON COLUMN public.leads.interest_type IS
  'Required when status = future (FR-21). Enforced at Edge Function layer (Zod), not DB CHECK.';

-- ────────────────────────────────────────────────────────────────────────────
-- updated_at trigger
-- ────────────────────────────────────────────────────────────────────────────
CREATE TRIGGER leads_set_updated_at
  BEFORE UPDATE ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ────────────────────────────────────────────────────────────────────────────
-- RLS
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leads FORCE  ROW LEVEL SECURITY;

DROP POLICY IF EXISTS leads_tenant_isolation ON public.leads;
CREATE POLICY leads_tenant_isolation ON public.leads
  FOR ALL
  TO authenticated
  USING      (tenant_id = public.auth_tenant_id())
  WITH CHECK (tenant_id = public.auth_tenant_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.leads TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- Indexes on leads
-- ────────────────────────────────────────────────────────────────────────────
-- FK indexes (every FK column indexed — arch §Database Patterns)
CREATE INDEX IF NOT EXISTS leads_tenant_id_idx
  ON public.leads (tenant_id);

CREATE INDEX IF NOT EXISTS leads_assigned_to_user_id_idx
  ON public.leads (assigned_to_user_id)
  WHERE assigned_to_user_id IS NOT NULL;

-- Duplicate detection: O(1) phone lookup
CREATE INDEX IF NOT EXISTS leads_phone_hash_idx
  ON public.leads (phone_hash);

-- Urgency sort: last_action_at tiebreaker within status tier (FR-17)
CREATE INDEX IF NOT EXISTS leads_tenant_status_last_action_idx
  ON public.leads (tenant_id, status, last_action_at DESC);

-- Follow-up calendar query (Story 3.5)
CREATE INDEX IF NOT EXISTS leads_next_followup_at_idx
  ON public.leads (tenant_id, next_followup_at)
  WHERE next_followup_at IS NOT NULL;

-- Admin name search: pg_trgm GIN index (arch Decision 22)
CREATE INDEX IF NOT EXISTS leads_name_search_trgm_idx
  ON public.leads USING GIN (name_search extensions.gin_trgm_ops)
  WHERE name_search IS NOT NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- lead_projects — junction table (multi-select Project per Lead, FR-1)
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.lead_projects (
  lead_id    uuid NOT NULL REFERENCES public.leads(id)    ON DELETE CASCADE,
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  tenant_id  uuid NOT NULL REFERENCES public.tenants(id)  ON DELETE RESTRICT,
  PRIMARY KEY (lead_id, project_id)
);

COMMENT ON TABLE public.lead_projects IS
  'Story 2.1 — Many-to-many: a Lead can reference multiple Projects (FR-1 Project multi-select).';

-- FK indexes
CREATE INDEX IF NOT EXISTS lead_projects_project_id_idx
  ON public.lead_projects (project_id);

CREATE INDEX IF NOT EXISTS lead_projects_tenant_id_idx
  ON public.lead_projects (tenant_id);

-- ────────────────────────────────────────────────────────────────────────────
-- RLS on lead_projects
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.lead_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_projects FORCE  ROW LEVEL SECURITY;

DROP POLICY IF EXISTS lead_projects_tenant_isolation ON public.lead_projects;
CREATE POLICY lead_projects_tenant_isolation ON public.lead_projects
  FOR ALL
  TO authenticated
  USING      (tenant_id = public.auth_tenant_id())
  WITH CHECK (tenant_id = public.auth_tenant_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.lead_projects TO authenticated;
