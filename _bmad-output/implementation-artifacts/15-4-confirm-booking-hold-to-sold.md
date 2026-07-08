# Story 15.4: confirm hold to sold on payment verification

Status: review  (migration 0078 written + applied + smoke ALL PASS 2026-06-28)

## Implementation (2026-06-28)

**File:** `nirman-crm/supabase/migrations/0078_confirm_booking.sql`

- `confirm_booking(p_hold_id, p_payment_verified)` SECURITY DEFINER. Guard tier IN (builder_head, team_leader) else `forbidden_role`; requires `p_payment_verified = true` else `payment_not_verified`. One txn: hold (`FOR UPDATE`, must be active) → released+`outcome='converted'`; unit → `sold` (must be `hold`, else `unit_not_held`); lead → `sold` via the **shipped status-change seam** (`UPDATE leads` + `log_timeline_event('status_changed',{from,to:'sold'})`) so the FR-34 mobile Sold-celebration fires unchanged; plus `unit_booked` timeline (new enum value).
- **Naming note:** `hold_outcome` enum value is `converted` (= AC's "confirmed"); semantically the hold converted to a sale.
- **Revert (AC5):** sold→available is head-only via the existing `change_unit_inventory_state('force_release')` (0074, builder_head-gated + logged). Non-head cannot revert. Full booking-revert (also reverting the lead) is a head-only follow-on.

**Tested (local runtime):** rep → forbidden_role; head no-payment → payment_not_verified; **team_leader confirm** → unit sold + lead sold + hold converted; status_changed→sold timeline (celebration seam) + unit_booked logged; **builder_head confirm** works; sold-unit revert: rep denied (permission_denied), head → available.

**Deferred:** mobile/admin "Confirm booking" action (payment_verified attestation) on the hold; the celebration itself is already shipped (7.2) and untouched.

## Story

As a Builder Head or Team Leader,
I want to confirm a hold as a booking when payment is verified,
so that the unit and lead are marked sold and the win is celebrated.

## Acceptance Criteria

1. **Given** `confirm_booking(p_hold_id, p_payment_verified)` **When** a user with `auth_role_tier() IN ('builder_head','team_leader')` confirms with `p_payment_verified = true` **Then** in one transaction: hold `released_at=now(), outcome='confirmed'`, unit → `sold`, lead → `sold`.
2. **And** the lead status→sold reuses the existing status-change → Timeline → FR-34 Sold-celebration seam (mobile celebration fires unchanged).
3. **And** a `front_line_rep` or `partner_agency` calling confirm gets `forbidden_role`.
4. **And** confirming without `p_payment_verified` is rejected.
5. **And** a sold unit cannot revert without a Builder Head override (logged).

## Tasks / Subtasks

- [ ] **Task 1 — Migration `0062_confirm_booking.sql`**: `confirm_booking` RPC (SECURITY DEFINER): guard tier IN (builder_head, team_leader); require `p_payment_verified`; one txn — update hold (released/confirmed), unit→sold (`status_version+1`), lead→sold via existing status-change path so `status_changed` Timeline + domain event fire (which the mobile FR-34 celebration listens to); log `unit_booked`.
- [ ] **Task 2 — Sold-celebration reuse**: confirm the lead status→sold writes the SAME `status_changed`→sold Timeline/domain event the mobile celebration already triggers on (Epic 7.2 / FR-34). No new celebration code.
- [ ] **Task 3 — Revert guard**: `sold→available` only via a head-only override RPC, logged.
- [ ] **Task 4 — Tests**: head + leader confirm works; rep/partner denied; no-payment rejected; celebration fires; sold revert blocked for non-head.

## Dev Notes

- Leaders CAN confirm (decided); margin still head-only. [Source: architecture-builder-ops-v2.md §13.2 matrix, §4.4]
- V2 = manual `payment_verified` attestation, NOT a gateway. [Source: A-15, §4.4]
- Reuse the shipped Sold-celebration seam — flipping the lead to sold through the normal status path is all that's needed. [Source: 7-2-sold-celebration-earned-moment-card.md; FR-34]
- Clears the hold timer implicitly (released → cron skips it).

## References
- [Source: epics.md#Story 15.4; architecture-builder-ops-v2.md §4.4, §13.2, A-15]
- [Source: 0021_mark_dead_restore_lead_fns.sql / status-change path; 7-2 celebration]
