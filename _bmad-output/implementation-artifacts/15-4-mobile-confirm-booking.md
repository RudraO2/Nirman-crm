---
baseline_commit: 596238c1176640da3f0b37b089fb220fab4ad2ac
---
# Story 15.4-mobile: confirm booking hold→sold (Flutter UI)

Status: done

<!-- Mobile-UI completion of Story 15.4. Backend confirm_booking() is DONE on prod/local
(migration 0078) — do NOT touch it. This is the deferred mobile action: a Confirm-booking action on a
held unit + payment-verified attestation. Builds on 14.3-mobile grid + 15.2-mobile hold/detail sheet.
Demo-slice step 4 (final). The Sold celebration (FR-34 / 7.2) already ships and fires unchanged. -->

## Story

As a Builder Head or Team Leader,
I want to confirm a hold as a booking once payment is verified,
so that the unit and lead are marked sold and the win is celebrated.

## Acceptance Criteria

1. **Given** a `hold` unit's detail sheet **When** a `builder_head`/`team_leader` taps "Confirm booking"
   and attests payment is verified **Then** the app calls `confirm_booking(p_hold_id, true)` and on
   success the unit flips to `sold` (via the existing Realtime refetch) with a clear "Booked!" success.
2. **And** confirming requires an explicit payment-verified attestation (a deliberate confirm step, not a
   single tap) — the app never sends `p_payment_verified = true` without the user affirming it.
3. **And** a `front_line_rep`/`partner_agency` who somehow reaches Confirm gets `forbidden_role` mapped
   to a calm "Only a manager can confirm a booking" message (no raw crash). The RPC is the gate — do not
   rely on a client-read `role_tier` for correctness (it may be absent from the JWT).
4. **And** the lead→sold transition (done server-side by confirm_booking through the shipped status-change
   seam) fires the existing FR-34 Sold celebration unchanged — this story adds NO celebration code and
   MUST NOT duplicate it; it only triggers the booking, then surfaces the win to the confirming user.
5. **And** a stale hold (already released/expired/converted, or the unit no longer `hold`) maps
   `hold_not_active`/`unit_not_held` to a calm "This hold is no longer active — refreshing" and the grid
   refetches to the true state. (Reverting a sold unit is head-only and backend-only — NOT in this story.)

## Tasks / Subtasks

- [x] **Task 1 — Repo: confirm_booking** (`features/inventory/data/inventory_repository.dart`) (AC: 1,3,5)
  - [x] `Future<void> confirmBooking(String holdId)` → `_supabase.rpc('confirm_booking',
        params: {'p_hold_id': holdId, 'p_payment_verified': true})`. (The attestation is enforced in the
        UI per AC2; the RPC also rejects `false`.)
  - [x] Typed `ConfirmException` mapping (sibling of HoldException): `forbidden_role` → notAllowed;
        `payment_not_verified` → a distinct flag (shouldn't happen given the UI always sends true, but map
        it); `hold_not_active`/`hold_not_found`/`unit_not_held` → a `stale` flag; else generic.
- [x] **Task 2 — Confirm action + attestation** (`features/inventory/ui/unit_detail_sheet.dart`) (AC: 1,2,3)
  - [x] On a `hold` unit's detail sheet (which already shows the 15.2 countdown + reads `activeHold`), add
        a "Confirm booking" button. Use the `activeHold` hold_id already fetched for the countdown.
  - [x] Tapping it opens a payment-verified attestation dialog: a checkbox "Payment is verified" that must
        be ticked to enable the "Confirm — mark Sold" button (deliberate two-step, AC2). Confirm calls the
        repo. Show in-flight state; disable during the call.
  - [x] On success: invalidate `projectUnitsProvider(projectId)` + `activeHold(unitId)`, close the sheet,
        show a celebratory "Booked! 🎉 Unit <no> sold" confirmation. On `ConfirmException.notAllowed` →
        "Only a manager can confirm a booking"; on `.stale` → "This hold is no longer active — refreshing"
        + invalidate; else generic.
  - [x] Show the Confirm button for hold units regardless of client tier (RPC gates); consistent with how
        15.2 handles receptionist. Do NOT gate on a client-read role_tier.
- [x] **Task 3 — Tests** (`test/features/inventory/`) (AC: 2,3,5)
  - [x] `ConfirmException` mapping: forbidden_role→notAllowed, hold_not_active/unit_not_held→stale,
        payment_not_verified→its flag, unknown→generic.
  - [x] Attestation dialog: the Confirm button is disabled until the checkbox is ticked (AC2).
  - [x] `flutter analyze` 0 errors; full suite green.

## Dev Notes

### The backend contract (already shipped — do NOT modify)
`confirm_booking(p_hold_id uuid, p_payment_verified boolean)` → jsonb `{hold_id, unit_id, lead_id,
status:'sold'}`. Guard: `auth_role_tier() IN ('builder_head','team_leader')` else `forbidden_role`
(42501); requires `p_payment_verified = true` else `payment_not_verified` (P0001). One txn: hold →
released + `outcome='converted'`; unit → `sold`; lead → `sold` via the shipped status-change seam
(`status_changed`→sold Timeline + domain event) so the mobile FR-34 Sold celebration fires unchanged;
`unit_booked` timeline logged. Other errors: `hold_not_found`, `hold_not_active` (already
released/expired/converted), `unit_not_held`. Revert sold→available is head-only via
`change_unit_inventory_state('force_release')` (0074) — backend only, NOT a mobile action here.
[Source: nirman-crm/supabase/migrations/0078_confirm_booking.sql; 15-4-confirm-booking-hold-to-sold.md]

### Builds on 15.2-mobile (done)
The held-unit detail sheet already reads `activeHold(unitId)` (for the countdown) — reuse that hold_id
for confirm. Same "flip only from the authoritative refetch, never optimistic" discipline as 15.2.
[Source: 15-2-mobile-hold-unit.md]

### Celebration reuse (AC4)
Do NOT write celebration code. confirm_booking flips the lead to sold through the normal status path,
which the shipped FR-34 / Story 7.2 Sold-celebration already listens for. When the confirming user next
views that lead / home, the celebration surfaces. This story only shows a booking-confirmed success on
the inventory sheet. [Source: 7-2-sold-celebration-earned-moment-card.md]

### Local verification (FREE — never prod)
Seed applied (`supabase/demo-builder-ops.local.sql`). Verify on the local stack via simulated-JWT (as
14.3/15.2 were): place a hold (head), then confirm with payment_verified=true → unit sold + lead sold;
front_line_rep confirm → forbidden_role; confirm with false → payment_not_verified; confirm an already
released hold → hold_not_active. [Source: nirman-crm/CLAUDE.md]

### Project Structure Notes
Additive within `features/inventory`. Only `unit_detail_sheet.dart` + `inventory_repository.dart` change;
attestation dialog can be a small private widget or a new `confirm_booking_dialog.dart`. No backend, no
migration.

### References
- [Source: epics.md#Story 15.4; architecture-builder-ops-v2.md §4.4, §13.2, A-15]
- [Source: nirman-crm/supabase/migrations/0078_confirm_booking.sql]
- [Source: 15-4-confirm-booking-hold-to-sold.md (backend record — deferred mobile action is this story)]
- [Source: 15-2-mobile-hold-unit.md; 7-2-sold-celebration-earned-moment-card.md]

### Review Findings

_Code review 2026-07-10 (3 lenses inline). 0 decision-needed, 0 patch, 0 defer — clean. Verified: AC2 attestation gate (Confirm disabled until checkbox ticked — widget-tested), AC5 no-optimistic-flip (sold only from refetch), BuildContext-safe async, ConfirmException mapping (notAllowed/stale/paymentNotVerified/generic), no celebration duplication (AC4 — lead→sold rides the shipped 7.2 seam). Guards verified live on the local stack. 175/175 suite, analyze 0. No backend touched._

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia / bmad-dev-story)

### Debug Log References

- `flutter analyze` 0 errors; `flutter test` full suite **175/175** (7 new: ConfirmException mapping +
  attestation-dialog gating; 32 total in features/inventory).
- Live verification on local Docker via simulated-JWT (rollback txns): builder_head hold→confirm(true)
  → **unit=sold + lead=sold**; confirm(false) → `payment_not_verified`; partner confirm → `forbidden_role`.

### Completion Notes List

- Confirm-booking action added to the held-unit detail sheet, reusing the 15.2 `activeHold` hold_id.
- **AC2 attestation:** `confirm_booking_dialog.dart` — "Confirm — mark Sold" stays disabled until the
  manager ticks "Payment is verified" (deliberate two-step); the app never sends `p_payment_verified`
  without that affirmation (repo always sends `true`, gated behind the dialog).
- **AC4 celebration:** no celebration code — confirm_booking flips the lead to sold via the shipped
  status seam, which the FR-34 / 7.2 Sold-celebration already listens for. This story only shows a
  "Booked! 🎉" success on the inventory sheet.
- **AC5:** the tile flips to sold only from the authoritative refetch (`invalidate(projectUnitsProvider)`)
  after the RPC confirms; `hold_not_active`/`unit_not_held` → calm "no longer active — refreshing".
- `_buildAction` switches the sheet's bottom CTA by unit status: available→Hold, hold→Confirm booking,
  sold/blocked→disabled.

### File List

**New**
- apps/mobile/lib/features/inventory/ui/confirm_booking_dialog.dart
- apps/mobile/test/features/inventory/confirm_test.dart

**Modified**
- apps/mobile/lib/features/inventory/data/inventory_repository.dart (confirmBooking + ConfirmException)
- apps/mobile/lib/features/inventory/ui/unit_detail_sheet.dart (confirm action + status-based CTA + import UnitHold; removed unused _HoldCountdownRow)

## Change Log

- 2026-07-10: Implemented mobile confirm-booking (Story 15.4) — Confirm action on held-unit sheet +
  payment-verified attestation dialog + `confirm_booking` RPC → hold→sold (lead→sold rides the shipped
  FR-34 celebration seam). Typed ConfirmException (notAllowed/stale/paymentNotVerified). 7 new tests
  (175/175 suite), analyze 0. Guards verified live (sold, payment_not_verified, forbidden_role). Status → done.
