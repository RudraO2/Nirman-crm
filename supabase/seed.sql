-- Story 1.1 (AC-6) — Seed V1 tenant
-- Idempotent: ON CONFLICT DO NOTHING ensures re-runs do not duplicate.
-- This file runs on every `supabase db reset` for local dev. For cloud, the same
-- INSERT is applied once via mcp__supabase__execute_sql during Story 1.1 dev.

INSERT INTO public.tenants (id, name, timezone)
VALUES (
  '00000000-0000-0000-0000-000000000001'::uuid,
  'Nirman Media',
  'Asia/Kolkata'
)
ON CONFLICT (id) DO NOTHING;

-- LOCAL-DEV-ONLY — dummy PII encryption key so create_lead_with_pii / bulk_import_leads
-- run in local tests. Prod's real 'lead_pii_key' vault secret is set out-of-band; this
-- seed only affects the local stack (`supabase db reset`), never prod. Idempotent.
SELECT vault.create_secret('local-dev-pii-key-not-a-real-secret', 'lead_pii_key')
WHERE NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'lead_pii_key');
