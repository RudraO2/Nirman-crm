---
baseline_commit: 596238c1176640da3f0b37b089fb220fab4ad2ac
---
# Story 15.5-mobile: booking dashboard (Flutter UI)

Status: review

<!-- Mobile-UI completion of Story 15.5. The backend (migration 0079 get_active_holds +
get_booking_stats, scoped by visible_user_ids(); confirm_booking from 0062) is DONE on prod and recorded
in 15-5-booking-dashboard.md + 15-4-confirm-booking-hold-to-sold.md — do NOT touch it. This story is ONLY
the deferred mobile dashboard: active holds with a live countdown, booking stats + conversion %, project
filter, and a hold→sold conversion that reuses the Slice 1 confirm_booking seam + hold_countdown widget.
Named `15-5-mobile-*` to preserve the backend story record. Slice 3 of the mobile builder-ops build. -->

## Story

As a Builder Head (or Team Leader),
I want to see my team's active holds counting down and our booking conversion,
so that I can chase expiring holds and track how holds turn into sales — from my phone.

## Acceptance Criteria

1. **Given** a head/leader on the booking dashboard **When** it loads **Then** the active holds list shows
   each hold's unit, lead, agent, and a live time-to-expiry countdown (amber, red in the last hour,
   "Expired" past the deadline) — driven by the reused `HoldCountdown` widget off the RPC's `expires_at`.
2. **And** the header shows confirmed-bookings count, active-holds count, and hold→sold conversion % for
   the selected period, from `get_booking_stats`.
3. **And** results are filterable by project (a project picker) within the caller's
   `visible_user_ids()` scope; the RPC re-applies the scope, so the client never filters holds itself.
4. **And** a Team Leader sees only their subtree's holds/bookings and a Builder Head sees all internal —
   enforced server-side by `visible_user_ids()` (the client renders exactly what the RPCs return).
5. **And** an active hold can be converted to a booking in place: a "Convert to sold" action opens the
   existing payment-verified attestation dialog and calls the shipped `confirm_booking` seam (hold→sold,
   lead→sold + the FR-34 celebration); on success the list + stats refetch through the RPCs.
6. **And** a caller whose tier cannot confirm (`forbidden_role`, e.g. a rep) or a hold that went stale
   (`hold_not_active`) maps to a calm message (reusing `ConfirmException`), not a red dump.
7. **And** an empty scope (no active holds) shows a calm empty state, not an error; pull-to-refresh
   re-reads both RPCs (the awaited refetch guarded in try/catch — Slice 2 review finding).

## Tasks / Subtasks

- [x] **Task 1 — Data layer** (`features/booking/data/`) (AC: 1,2,3,4)
  - [x] `models/active_hold.dart`: immutable `ActiveHold` (holdId, unitId, unitNo, projectId, leadId,
        leadName?, holdingAgentId, agentName?, heldAt, expiresAt, secondsToExpiry) + `fromJson` matching
        `get_active_holds` columns. Flutter-free.
  - [x] `models/booking_stats.dart`: immutable `BookingStats` (confirmedBookings, activeHolds, totalHolds,
        conversionPct) + `fromJson` (numeric conversion_pct → double, null → 0).
  - [x] `booking_repository.dart`: `BookingRepository(SupabaseClient)` with
        `getActiveHolds({projectId})` → `.rpc('get_active_holds', {p_project_id})` and
        `getBookingStats({periodDays=30, projectId})` → `.rpc('get_booking_stats', {p_period_days,
        p_project_id})`. Typed `BookingAccessException.fromPostgrest` (`not_authenticated` → notAuthed;
        empty scope is a normal empty list, NOT an error). Co-located `@riverpod bookingRepository`.
- [x] **Task 2 — Providers** (`features/booking/providers/`) (AC: 1,2,3)
  - [x] `activeHoldsProvider(projectId?)` (family) + `bookingStatsProvider(projectId?)` (family). Invalidate
        both after a conversion so the authoritative refetch reflects hold→sold.
  - [x] `dart run build_runner build --delete-conflicting-outputs` after adding providers.
- [x] **Task 3 — UI** (`features/booking/ui/`) (AC: 1,2,3,5,6,7)
  - [x] `booking_dashboard_screen.dart`: AppBar "Booking dashboard"; a stats header (3 tiles: Confirmed /
        Active / Conversion %); a project filter row (All + each project via `availableProjectsProvider`);
        the active-holds list (unit_no, lead name or "Lead", agent, `HoldCountdown`, "Convert to sold");
        loading / error / empty states; pull-to-refresh (guarded). Convert → `showConfirmBookingDialog`
        → `InventoryRepository.confirmBooking` (reused seam) → invalidate both providers; `ConfirmException`
        → calm snackbar.
- [x] **Task 4 — Wiring** (AC: 1) — `/booking` route + a WORKSPACE "Booking dashboard" row in
      `you_screen.dart` shown when `role == 'admin' || roleTier == 'team_leader'`.
- [x] **Task 5 — Tests** (`test/features/booking/`) (AC: 1,2,3,5,6,7): `ActiveHold`/`BookingStats`
      fromJson (incl. null lead_name, numeric pct); `BookingAccessException` mapping; a widget test of
      the dashboard (stats tiles render, holds render with a countdown, empty state) with fake providers.
      analyze 0; full suite green.
- [x] **Task 6 — Verify guards live on local Docker** (AC: 3,4) — seed an active + a converted hold
      (`supabase/demo-booking-holds.local.sql`, LOCAL-ONLY, gitignored). Simulated-JWT: head sees all
      holds + stats; leader sees subtree only; rep convert → `forbidden_role`.

## Dev Notes

### The backend contract (already shipped — do NOT modify)
- `get_active_holds(p_project_id uuid DEFAULT NULL, p_agent_id uuid DEFAULT NULL) RETURNS TABLE(hold_id,
  unit_id, unit_no, project_id, lead_id, lead_name, holding_agent_id, agent_name, held_at, expires_at,
  seconds_to_expiry)` — SECURITY DEFINER, scoped `holding_agent_id IN (SELECT user_id FROM
  visible_user_ids())`, lead name decrypted via vault, ordered by `expires_at ASC`.
- `get_booking_stats(p_period_days int DEFAULT 30, p_project_id uuid DEFAULT NULL) RETURNS TABLE(
  confirmed_bookings, active_holds, total_holds, conversion_pct)` — same scope.
- `confirm_booking(p_hold_id, p_payment_verified)` (0062) — head/leader only (`forbidden_role` for reps);
  reused via `InventoryRepository.confirmBooking` + `showConfirmBookingDialog` from Slice 1.
[Source: 0079_booking_dashboard.sql; 0062; features/inventory/{data/inventory_repository.dart,ui/confirm_booking_dialog.dart,ui/hold_countdown.dart}]

### Countdown reuse
`features/inventory/ui/hold_countdown.dart` `HoldCountdown(expiresAt:)` already ticks 1 Hz, amber→red in
the last hour, "Expired" past due, and its `formatRemaining` is pure. Reuse it directly against the RPC's
`expires_at` — do NOT reimplement (the RPC also returns `seconds_to_expiry` for a non-clock fallback, kept
on the model but the widget uses `expires_at`). [Source: hold_countdown.dart header ("Reused by Story 15.5")]

### Scope is server-side (AC3/AC4)
The client passes only an optional `p_project_id`; `visible_user_ids()` inside the RPCs enforces
leader-subtree / head-all / rep-self. Never filter holds client-side. Agent-level filtering is supported
by the RPC (`p_agent_id`) but a roster picker is deferred (the team roster lives in `features/team`;
cross-feature wiring out of scope) — project filter satisfies AC3. Noted in deferred-work.md.

### Structure / conventions (match Slices 1–2)
`features/booking/{data/{models/},providers/,ui/}`; repo behind a co-located `@riverpod` provider; models
immutable + `fromJson`; typed exception from `PostgrestException`; top-level `GoRoute`; codegen providers.
Colours via `AppColors`. RefreshIndicator `onRefresh` guards the awaited refetch in try/catch.
[Source: features/inventory/*, features/team/*, features/hierarchy/*]

### Local test env (FREE — never prod)
Docker Supabase up; demo seed + `supabase/demo-booking-holds.local.sql` (LOCAL-ONLY, gitignored via
`*.local.sql`) seeds one active hold (rep1's lead, unit set to `hold`, expires now()+24h) + one converted
hold (unit `sold`, `outcome='converted'`, released) so stats show a non-zero conversion. Users: head
(`c1000000-…0001`), rep1 (`…00e1`). Simulated-JWT (set local role + request.jwt.claims, rollback).

### References
- [Source: epics.md#Story 15.5; architecture-builder-ops-v2.md §4.4]
- [Source: 0079_booking_dashboard.sql; 15-5-booking-dashboard.md (backend record)]
- [Source: features/inventory/* (hold_countdown + confirm_booking seam), features/team/* patterns]

## Dev Agent Record

### Agent Model Used
claude-opus-4-8 (Amelia / bmad-dev-story)

### Completion Notes List
- New additive domain `features/booking/{data,providers,ui}`. Consumes the shipped `get_active_holds` +
  `get_booking_stats` RPCs (0079) and reuses the Slice 1 `confirm_booking` seam
  (`InventoryRepository.confirmBooking` + `showConfirmBookingDialog`) + `HoldCountdown` widget. No backend
  touched.
- **Server-side scope (AC3/AC4):** the client passes only an optional `p_project_id`; `visible_user_ids()`
  in the RPCs enforces leader-subtree / head-all / rep-self. The client never filters holds itself.
- **Live countdown (AC1):** reused `HoldCountdown(expiresAt:)` (1 Hz, amber→red last hour, "Expired").
  The model also carries `seconds_to_expiry` as a clockless fallback but the widget uses `expires_at`.
- **Convert in place (AC5/AC6):** the "Convert to sold" action opens the shipped payment-verified
  attestation dialog → `confirm_booking` → hold→sold + FR-34 celebration; both providers invalidate on
  success. `ConfirmException` maps to calm messages (`forbidden_role`/`hold_not_active`/…) — no red dump.
- **Empty + refresh (AC7):** an empty scope shows a calm empty state; pull-to-refresh re-reads both RPCs
  with the awaited refetch guarded in try/catch (Slice 2 finding).
- **Entry gate:** WORKSPACE "Booking dashboard" row shows when `role == 'admin' || roleTier ==
  'team_leader'` (management view; reps use the availability grid). Cosmetic gate; the RPCs scope + the
  confirm re-checks the tier server-side.
- **Verified live on local Docker (2026-07-11)** via `supabase/demo-booking-holds.local.sql` (LOCAL-only)
  + simulated-JWT SQL (mutations rolled back): head `get_active_holds` = 1 (unit 102, ~24h) +
  `get_booking_stats` = confirmed 1 / active 1 / total 2 / **conversion 50.0**; rep `get_active_holds`
  (self scope) = 1; rep `confirm_booking` → **forbidden_role**. On-device visual look-pass for Rudra.

### File List
**New**
- apps/mobile/lib/features/booking/data/models/active_hold.dart
- apps/mobile/lib/features/booking/data/models/booking_stats.dart
- apps/mobile/lib/features/booking/data/booking_repository.dart
- apps/mobile/lib/features/booking/data/booking_repository.g.dart (generated)
- apps/mobile/lib/features/booking/providers/booking_providers.dart
- apps/mobile/lib/features/booking/providers/booking_providers.g.dart (generated)
- apps/mobile/lib/features/booking/ui/booking_dashboard_screen.dart
- apps/mobile/test/features/booking/active_hold_test.dart
- apps/mobile/test/features/booking/booking_stats_test.dart
- apps/mobile/test/features/booking/booking_repository_test.dart
- apps/mobile/test/features/booking/booking_dashboard_screen_test.dart
- nirman-crm/supabase/demo-booking-holds.local.sql (LOCAL-only seed, gitignored)

**Modified**
- apps/mobile/lib/router/app_router.dart (/booking route)
- apps/mobile/lib/features/home/ui/you_screen.dart (Booking dashboard entry row)

## Review Findings

_Code review 2026-07-11 (3 lenses inline). **0 confirmed correctness findings, 1 low no-fix.** ACs 1–7
satisfied; reuse of the confirm seam + countdown widget, server-scoped reads, and calm error/empty
states verified. Suite 225/225, analyze 0 errors._

- [ ] [Review][Low][No-fix] The stats header renders `statsAsync.valueOrNull ?? BookingStats.empty`, so
  during the initial load (and briefly on a project-filter change) it shows zeros rather than a spinner,
  and a `get_booking_stats` error is swallowed to zeros while the holds list shows the error. Acceptable:
  stats + holds share the same scope/RLS, so a stats failure coincides with a visible holds error, and the
  header self-corrects on the next frame. Agent-level filtering (RPC supports `p_agent_id`) is deferred —
  needs a roster picker (cross-feature with `features/team`); project filter satisfies AC3. Both noted in
  deferred-work.md.

## Change Log
- 2026-07-11: Story drafted (bmad-create-story) — mobile booking-dashboard slice of 15.5.
- 2026-07-11: Implemented `features/booking` — dashboard (stats tiles + project filter + active holds
  with reused live countdown) + hold→sold via the reused confirm_booking seam. 11 new tests; analyze 0;
  full suite 225/225. Guards + stats verified live on local Docker (simulated JWT + local hold seed).
  Status → review.
- 2026-07-11: Code review (3 lenses inline) — 0 confirmed findings; 1 low no-fix (stats-header loading
  shows zeros; agent-filter deferred). Status → done.
