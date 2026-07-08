# Story 13.6: excel import is reclaim-aware

Status: review  (migration 0068 written + self-reviewed; web import UI update + apply deferred)

## Story

As an admin,
I want bulk import to honour the new lock/reclaim rules,
so that importing does not wrongly reject reclaimable leads nor silently reassign locked ones.

## Acceptance Criteria

1. **Given** `bulk_import_leads` **When** a file is imported **Then** incoming `phone_hash`es are classified in a single set-based pass into {new → insert, reclaimable → reassign-in-place, locked → skip with reason} — NOT per-row `FOR UPDATE` calls.
2. **And** `check_phone_hashes` returns lock-state (not just existence) so classification is correct.
3. **And** the import summary reports counts per class (imported / reclaimed / skipped-locked / errors).
4. **And** rows missing primary phone are rejected; rows missing secondary phone import as Incomplete (A-11).

## Tasks / Subtasks

- [ ] **Task 1 — `check_phone_hashes` returns lock-state**: extend (`0052`) to return per-hash {exists, owner, lock_started_at, last_action_at, reclaimable?} instead of bare existence.
- [ ] **Task 2 — `bulk_import_leads` set-based classify**: one query joins incoming hashes against `leads` to bucket new/reclaimable/locked; INSERT new, UPDATE reassign reclaimable (reset lock_started_at, log `lead_reclaimed`), skip locked with reason. No 5,000 per-row `FOR UPDATE`.
- [ ] **Task 3 — Summary**: extend the import summary modal/response with the 4 counts.
- [ ] **Task 4 — Tests**: file mixing new/reclaimable/locked phones classifies correctly; locked not reassigned; reclaimable reassigned; missing-primary rejected; missing-secondary → Incomplete.

## Dev Notes

- Do 13.5 first (defines lock semantics). [Source: architecture-builder-ops-v2.md §5.2 excel-import]
- Existing import: `0052_bulk_import.sql` (`bulk_import_leads`, `check_phone_hashes`) — both `IS DISTINCT FROM 'admin'` guarded (already NULL-safe). Reuse round-robin distribution. [Source: 0052]
- Set-based pass avoids the long-txn/lock-ordering problem Amelia flagged. [Source: party review; §5.2]
- Admin web import UI (Story 6.1) summary needs the new counts surfaced. [Source: 6-1 story]

## References
- [Source: epics.md#Story 13.6; architecture-builder-ops-v2.md §5.2, §10 flag 1]
- [Source: 0052_bulk_import.sql]

## Implementation (2026-06-27)

**File:** `nirman-crm/supabase/migrations/0068_import_reclaim_aware.sql`

- `check_phone_hashes` → DROP+CREATE returning `(phone_hash, locked)` — `locked = now()<lock_started_at+90d AND last_action_at>now()-30d`. Adding a column is **non-breaking** for existing callers (they read `phone_hash`).
- `bulk_import_leads` (same sig, CREATE OR REPLACE, body from 0052): cross-db step now classifies each existing phone — locked → skip (duplicates_skipped); reclaimable → reassign in place to the round-robin employee + reset lock + `lead_reclaimed`(batch_id) + count `reclaimed`; none → insert new with `lock_started_at=now()`. Source mapping extended for cold_call/employee_referral. Return adds `reclaimed`.

**Self-review:** import is one txn / low-concurrency → classify-SELECT without FOR UPDATE is acceptable (no 5000-lock concern). Imported NEW leads do not auto-gen customer_code (issued at interactive registration) — acceptable for V2, noted. `v_employee_id` computed before classify for reclaim assignment.

**Deferred:** admin-web import preview/summary UI to consume `locked` + show `reclaimed` count. Apply.

**Status:** backend code-complete, awaiting apply + web UI.
