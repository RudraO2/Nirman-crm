# Story 6.1 — Excel Bulk Import with Column Synonym Matching and Distribution

**Epic:** 6 — Bulk Data Operations  
**Status:** done  <!-- 2026-07-12 (audit M): was stale "in_progress" — shipped long ago per git + sprint-status.yaml (epic-6: done) -->  
**Stack:** apps/admin (Next.js) + Supabase migration 0052

## Acceptance Criteria

- AC-1: Upload .xlsx → columns auto-matched via synonym whitelist
- AC-2: Unmatched columns show manual-map dropdown (9 CRM fields + Ignore)
- AC-3: Preview shows first 10 rows, total rows, intra-file dupes, cross-db dupes, missing-phone count
- AC-4: Select N Employees → "Distribute Equally" → round-robin assignment
- AC-5: `is_incomplete = true` for rows missing any non-phone field
- AC-6: Each Lead's Timeline records `imported` event with `batch_id` in payload
- AC-7: Rows missing Phone are rejected (errors++)
- AC-8: Intra-file + cross-db duplicates are skipped (duplicates_skipped++)
- AC-9: Import summary shows X imported, Y duplicates skipped, Z errors

## Files Changed

### New — Migration
- `nirman-crm/supabase/migrations/0052_bulk_import.sql`
  - `check_phone_hashes(p_hashes text[])` — returns existing phone_hash matches for tenant
  - `bulk_import_leads(p_rows jsonb, p_employee_ids uuid[])` — full import with dedup + PII

### New — Admin UI
- `nirman-crm/apps/admin/src/app/(app)/import/types.ts`
- `nirman-crm/apps/admin/src/app/(app)/import/actions.ts` — server actions (xlsx server-side only)
- `nirman-crm/apps/admin/src/app/(app)/import/page.tsx` — server component
- `nirman-crm/apps/admin/src/components/import/import-wizard.tsx` — client wizard

### Modified
- `nirman-crm/apps/admin/package.json` — add `xlsx: ^0.18.5`
- `nirman-crm/apps/admin/src/app/(app)/layout.tsx` — add Import nav link after Activity

## Synonym Whitelist (exact per addendum)

| CRM Field    | Synonyms                                              |
|--------------|-------------------------------------------------------|
| Name         | name, customer name, lead name, client name, full name |
| Phone        | phone, mobile, number, contact, mob, cell             |
| Project      | project, project name, development                    |
| PropertyType | property type, type, unit type, property              |
| Location     | location, area, city, address                         |
| Budget       | budget, budget range, price, price range              |
| TicketSize   | ticket size, bhk, configuration, config               |
| Source       | source, lead source, channel                          |
| Remarks      | remarks, notes, comments, comment                     |

Match algo: lowercase+trim both; match if synonym⊂header OR header⊂synonym; longest synonym wins.

## Backend Notes

- `imported` already in `timeline_event_type` enum (migration 0012 line 39) — no ALTER needed
- PII encryption: same vault/pgcrypto pattern as `create_lead_with_pii` (migration 0016)
- Round-robin: `p_employee_ids[(i % array_length(p_employee_ids,1)) + 1]` where i = row index
- budget_min = budget_max = CAST(budget_raw AS bigint), NULL on failure
- source_raw → 'referral'|'associate'|'ad'|'walk_in' (default walk_in)
