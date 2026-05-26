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
