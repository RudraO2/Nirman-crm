# Story 16.2: log an amendment against a unit

Status: review  (migration 0081 written + applied + smoke ALL PASS 2026-06-28)

## Implementation (2026-06-28)

**File:** `nirman-crm/supabase/migrations/0081_log_amendment.sql`

- `log_amendment(unit, lead, description)` SECURITY DEFINER. Guards: `partner_agency` → `forbidden_role`; unit must exist in tenant + be `hold`|`sold` (else `unit_not_amendable`); lead must be in tenant + assigned within `visible_user_ids()` (else `lead_not_visible`); description required.
- Creates `amendments` row (status `requested`) and **dual-logs**: `log_amendment_event('logged', →requested, description)` + `log_timeline_event(lead,'amendment_logged',…)` (FR-19 reuse → shows on lead card). New `amendment_logged` timeline enum value (bare ADD VALUE). Returns amendment id.

**Tested (local runtime):** rep logs on held unit → amendment requested + 1 amendment_event + 1 lead_timeline (dual-log); available unit → unit_not_amendable; out-of-visibility rep → lead_not_visible; partner_agency → forbidden_role.

**Deferred:** mobile/admin "Log amendment" action UI.

## Story

As a salesperson,
I want to log a client's requested modification against their held/booked unit,
so that the change request is captured against the right unit and lead.

## Acceptance Criteria

1. **Given** `log_amendment(unit_id, lead_id, description)` **When** an agent (not `partner_agency`) logs an amendment against a unit on `hold` or `sold` linked to their (visible) lead **Then** an `amendments` row is created in `requested` status and an `amendment_logged` event appended.
2. **And** a corresponding entry is appended to the linked lead's existing Timeline (FR-19 reuse) so it surfaces on the lead card.
3. **And** logging against a unit not on hold/sold, or outside the caller's visibility, is rejected.
4. **And** a `partner_agency` caller gets `forbidden_role`.

## Tasks / Subtasks

- [ ] **Task 1 — `log_amendment` RPC** (SECURITY DEFINER): guard `auth_role_tier() <> 'partner_agency'`; validate unit status IN (hold, sold) AND lead visible to caller (`visible_user_ids()`); INSERT amendment (requested); append `amendment_logged` to amendment_events AND `log_timeline_event` on the lead (new `amendment_logged` timeline type).
- [ ] **Task 2 — Mobile/admin**: "Log amendment" action on a held/sold unit's lead; description input.
- [ ] **Task 3 — Tests**: valid log creates + dual-logs; non-hold/sold rejected; out-of-visibility rejected; partner denied.

## Dev Notes

- Dual-log: amendment_events (own trail) + lead Timeline (FR-19 reuse so it shows on the lead card). [Source: architecture-builder-ops-v2.md §6]
- Visibility via `visible_user_ids()` (12.5). [Source: §2.2]
- Notify wiring is 16.4.

## References
- [Source: epics.md#Story 16.2; architecture-builder-ops-v2.md §6]

> **0084 hardening (2026-06-28 review):** amendment requires the lead actually holds/booked the unit (lead_not_linked_to_unit). See builder-ops-backend-review-2026-06-28.md.
