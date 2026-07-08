# Story 15.5: booking dashboard

Status: review  (migration 0079 written + applied + scope/conversion smoke ALL PASS 2026-06-28; dashboard UI deferred)

## Implementation (2026-06-28)

**File:** `nirman-crm/supabase/migrations/0079_booking_dashboard.sql`

- `get_active_holds(project?, agent?)` — active holds (`released_at IS NULL`) scoped to `visible_user_ids()` (head→all internal, leader→subtree, rep→self). Returns unit/lead/agent + `seconds_to_expiry` (GREATEST(0, epoch(expires_at-now))) for the client countdown; lead name decrypted via vault. Project/agent filters.
- `get_booking_stats(period_days, project?)` — `confirmed_bookings` (outcome='converted'), `active_holds`, `total_holds`, `conversion_pct` = converted/total over the period; same `visible_user_ids()` scope + project filter.

**Tested (local runtime, hierarchy e2 head ⊃ e4 leader ⊃ e1 rep; e5 rep under head):** head get_active_holds=2 (countdown 86400, lead_name decrypted); leader=1 (subtree only); after confirming e1's hold → head stats confirmed=1/active=1/total=2/conversion=50.0; leader stats (scoped) confirmed=1/total=1/conversion=100.0.

**Deferred:** admin/mobile dashboard UI (live countdown widget, conversion chart) — read RPCs are ready.

## Story

As a Builder Head,
I want to see active holds and confirmed bookings,
so that I can track conversion and expiring holds.

## Acceptance Criteria

1. **Given** the booking dashboard read RPCs **When** I open it **Then** active holds list unit, lead, agent, and time-to-expiry countdown.
2. **And** confirmed-bookings count for the period + hold→sold conversion % are shown.
3. **And** results are filterable by project and by agent/team within the caller's `visible_user_ids()` scope.
4. **And** a Team Leader sees only their subtree's holds/bookings.

## Tasks / Subtasks

- [ ] **Task 1 — Read RPCs**: `get_active_holds()` (unit, lead, agent, expires_at) + `get_booking_stats(period)` (confirmed count, hold→sold %); both scope `holding_agent_id IN (SELECT user_id FROM visible_user_ids())`.
- [ ] **Task 2 — Admin/mobile dashboard**: active holds with live countdown; bookings + conversion.
- [ ] **Task 3 — Tests**: head sees all; leader sees subtree only; countdown matches `expires_at`; conversion math correct.

## Dev Notes

- Scope via `visible_user_ids()` (12.5) — leaders subtree, head all. [Source: architecture-builder-ops-v2.md §2.2, §4.4]
- Countdown is client-side from `expires_at`.
- Reuses TanStack Query + Recharts (web) / fl_chart (mobile) patterns. [Source: architecture.md Decisions 10/18]

## References
- [Source: epics.md#Story 15.5; architecture-builder-ops-v2.md §4.4]
