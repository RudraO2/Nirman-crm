# Story 13.2: capture and validate secondary phone

Status: review  (create + edit paths done + self-reviewed; mobile form + apply deferred)

## Story

As an employee,
I want secondary phone required to complete a lead,
so that every complete lead has a backup contact.

## Acceptance Criteria

1. **Given** the create/edit lead RPC **When** I save a lead with a 10-digit secondary phone **Then** it is normalized via existing `normalize_phone()`, encrypted with `lead_pii_key`, and `secondary_phone_hash` computed.
2. **And** a lead cannot reach `is_incomplete = false` without a valid secondary phone (quick-capture per FR-2 still allows primary-only Incomplete save).
3. **And** an invalid secondary phone (≠10 digits after normalize) is rejected with a field error.
4. **And** budget + configuration (`ticket_size`) are surfaced as registration-step fields and required for Complete (FR-43).

## Tasks / Subtasks

- [ ] **Task 1 — RPC rework**: extend `create_lead_with_pii` / the edit RPC (`0016`/`0019`) to accept + encrypt secondary phone; recompute completeness to include secondary phone, budget, configuration. Keep encrypt/hash identical to primary.
- [ ] **Task 2 — Completeness rule**: `is_incomplete=false` requires (existing fields) + secondary phone + budget + ticket_size. Quick-capture (primary + status only) still saves Incomplete.
- [ ] **Task 3 — Mobile form**: new-lead/edit sheets add secondary phone field (validated) + surface budget/config on the registration step. `flutter analyze` 0.
- [ ] **Task 4 — Tests**: complete blocked without secondary phone; invalid rejected; quick-capture still works.

## Dev Notes

- Reuse `normalize_phone()` (`0009`) + vault `lead_pii_key` encrypt (`0016`). No new crypto. [Source: 0009, 0016]
- Do NOT add a NOT NULL constraint on secondary phone (would break shipped rows + quick-capture). Enforce in RPC + form only. [Source: architecture-builder-ops-v2.md §10 flag 4]
- 13.5 reworks `create_lead_with_pii` for dedup; coordinate so secondary-phone capture and the lock branch land coherently (13.2 may merge into 13.5's rework, or 13.2 lands first then 13.5 extends). Recommend: 13.2 adds the column handling; 13.5 adds the lock branch. Sequence 13.2 → 13.5.

## References
- [Source: epics.md#Story 13.2; architecture-builder-ops-v2.md §5.1, §10 flag 4]
- [Source: 0016_create_lead_with_pii.sql, 0019_get_lead_by_id_and_update.sql]

## Implementation (2026-06-27)

**Files:** `nirman-crm/supabase/migrations/0063_lead_secondary_phone.sql` · edited `supabase/functions/create-lead/index.ts`.

- `0063`: DROP old 15-arg `create_lead_with_pii` + CREATE 17-arg (adds `p_secondary_phone_raw`, `p_secondary_phone_hash` DEFAULT NULL). Encrypts secondary with vault `lead_pii_key`, inserts `secondary_phone_encrypted` + `secondary_phone_hash`. Body otherwise faithful to 0016; GRANT re-issued for the new signature.
- `create-lead` edge fn: `LeadSource` enum → 6 values (cold_call, employee_referral); `secondary_phone` schema field (optional); normalize+hash with validation (invalid → `validation_error`); `computeIsIncomplete` now requires secondary phone (budget+config already required); rpc passes the two new params (named → order-independent).

**Self-review:** named-param rpc + `DEFAULT NULL` makes the fn back-compatible. Secondary hash stored, never wired to dedup (A-11). Quick-capture (primary-only) still saves Incomplete.

**REMAINING (this story not fully closed):** the **edit path** — `update-lead` edge fn + `get_lead_by_id_and_update` RPC (0019) need the symmetric secondary-phone handling so a user can *complete* an Incomplete lead by adding secondary phone (AC: "complete an Incomplete lead"). Create path is the template. Tracked as the open part of 13.2.

**Status:** create-path code-complete; edit-path + mobile form + apply remaining.

## Implementation — edit path (closes 13.2)

**Files:** `nirman-crm/supabase/migrations/0064_update_lead_secondary_phone.sql` · edited `supabase/functions/update-lead/index.ts`.

- `0064`: DROP old 17-arg `update_lead_with_pii` + CREATE 19-arg (adds `p_secondary_phone_raw`, `p_secondary_phone_hash` DEFAULT NULL). UPDATE sets `secondary_phone_encrypted` + `secondary_phone_hash`. Body faithful to 0019; REVOKE PUBLIC/anon + GRANT authenticated re-issued for the new signature.
- `update-lead` edge fn: mirrors create-lead — `LeadSource` 6 values, `secondary_phone` schema, completeness requires it, normalize+hash+validate, rpc passes the two params.

**Self-review:** create & edit edge fns now symmetric (same normalize/validate/hash + completeness rule). Completing an Incomplete lead by adding a valid secondary phone now flips `is_incomplete=false`. Named-param + DEFAULT NULL back-compat.

**Status:** backend create+edit code-complete; mobile form fields + apply remaining.
