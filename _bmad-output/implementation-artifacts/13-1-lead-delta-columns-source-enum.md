# Story 13.1: lead delta columns and source enum extension

Status: review  (migration 0062 written + self-reviewed; apply deferred)

## Story

As a developer,
I want the new lead columns and two new source values added additively,
so that registration v2 fields exist without disturbing shipped lead data.

## Acceptance Criteria

1. **Given** migration `0063_lead_deltas.sql` **When** applied **Then** `public.leads` gains `secondary_phone_encrypted bytea`, `secondary_phone_hash text`, `customer_code text`, `visit_count int NOT NULL DEFAULT 0`, `source_agency_id uuid REFERENCES agencies(id)`, `lock_started_at timestamptz`.
2. **And** partial unique index `leads_tenant_customer_code_idx (tenant_id, customer_code) WHERE customer_code IS NOT NULL` exists.
3. **And** `lead_source` enum gains `cold_call` and `employee_referral` (each `ALTER TYPE ... ADD VALUE` in its OWN statement; `referral` retained as "reference").
4. **And** existing leads unaffected (all new columns nullable/defaulted).
5. **And** `secondary_phone_hash` is NOT referenced by any duplicate-block path (A-11).

## Tasks / Subtasks

- [ ] **Task 1 — Migration `0063`**: `ALTER TABLE public.leads ADD COLUMN ...` (6 cols); partial unique index; `ALTER TYPE public.lead_source ADD VALUE 'cold_call'` then `ADD VALUE 'employee_referral'` (separate statements — `ADD VALUE` can't share a txn with dependent DDL on older PG; keep each standalone). Header comment: FR-42, Story 13.1.
- [ ] **Task 2 — Apply** via `db push --linked`. Confirm `migration list` head before (should be 0062 if 14/15 landed first, else sequential — verify actual head).
- [ ] **Task 3 — Regenerate types**; update mobile `Lead` freezed model + `build_runner`.

## Dev Notes

- Mirror PII pattern from `0009`/`0016`: encrypt with vault `lead_pii_key`, hash via `sha256(normalize_phone())`. `secondary_phone_hash` computed for future use only — NOT a dedup trigger (A-11). [Source: 0009, 0016, A-11]
- Enum `ADD VALUE` is irreversible — list locked at 6 (walk_in, referral, associate, ad, cold_call, employee_referral). [Source: architecture-builder-ops-v2.md §5.1, §10 flag 3]
- `lock_started_at` is the FR-47 anchor consumed by 13.5. Leave nullable here; 13.5 migration backfills `= now()`.
- Migration numbering: arch maps this `0063`, but actual sequence depends on which epics land first. **Always `supabase migration list` first**; use the true next number. [Source: CLAUDE.md]

## References
- [Source: epics.md#Story 13.1; architecture-builder-ops-v2.md §5.1]
- [Source: 0009_create_leads.sql, 0016_create_lead_with_pii.sql, 0010 unique constraint]

## Implementation (2026-06-27)

**File:** `nirman-crm/supabase/migrations/0062_lead_deltas.sql` (actual number; arch said 0063 — sequential after Epic 12's 0057–0061).

- Bare `ALTER TYPE lead_source ADD VALUE IF NOT EXISTS 'cold_call' / 'employee_referral'` (irreversible, list locked at 6) before the txn block.
- `leads` += `secondary_phone_encrypted, secondary_phone_hash, customer_code, visit_count(NOT NULL DEFAULT 0), source_agency_id(FK agencies), lock_started_at` — all `IF NOT EXISTS`, nullable/defaulted → existing rows untouched.
- Partial unique `leads_tenant_customer_code_idx (tenant_id, customer_code) WHERE NOT NULL`; FK index on source_agency_id.

**Self-review:** additive only; `visit_count NOT NULL DEFAULT 0` safe on backfill; `secondary_phone_hash` deliberately NOT wired to any dedup-block (A-11); `lock_started_at` left NULL here, backfilled `now()` in 13.5.

**Status:** code-complete, awaiting apply.
