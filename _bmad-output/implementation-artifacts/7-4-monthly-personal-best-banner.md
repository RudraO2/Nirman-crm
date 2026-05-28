---
baseline_commit: 3b8df2f
---
# Story 7.4: Monthly Personal Best banner

Status: done

## Story

As an Employee,
I want to see last month's Sold count vs my all-time monthly best in the first week of each month, with a banner if I exceed my best,
so that I have a personal reference point and earn a moment when I outperform myself.

## Acceptance Criteria

1. **Given** I am within the first 7 calendar days of a new month (tenant tz) **When** I open home **Then** a "Previous month" card appears below the personal stats card showing my Sold count last month and my all-time monthly best.
2. **Given** the 8th or later **Then** the "Previous month" card no longer appears.
3. **Given** at any point this month my "Sold this month" exceeds my previous all-time monthly best **When** the threshold is crossed **Then** a banner appears: "New personal best — N closed this month!" persisting until dismissed or end of month.
4. No comparison to other Employees anywhere.

## Tasks / Subtasks

- [x] **Task 1 — Migration `0034`: `get_monthly_best()` RPC** (AC: 1,2,3)
  - [x] SECURITY DEFINER, caller-scoped, tenant-tz. RETURNS `(this_month_sold int, last_month_sold int, all_time_best int, day_of_month int)`.
  - [x] Per-lead sold month = `date_trunc('month', max(status_changed→sold occurred_at) AT TIME ZONE tz)`; monthly counts grouped. `this_month_sold` = current tenant-month; `last_month_sold` = current−1; `all_time_best` = MAX(count) over months **before** current (prior best; 0 if none). `day_of_month` = `extract(day FROM now() AT TIME ZONE tz)`.
  - [x] `REVOKE … FROM PUBLIC, anon; GRANT … TO authenticated`.
- [x] **Task 2 — Mobile model + provider** (AC: 1,3)
  - [x] `MonthlyBest` model (`features/motivation/data/models/monthly_best.dart`): `thisMonthSold, lastMonthSold, allTimeBest, dayOfMonth`; derived getters `showPreviousMonthCard => dayOfMonth <= 7`, `isNewBest => thisMonthSold > allTimeBest && thisMonthSold > 0`.
  - [x] `MotivationRepository.getMonthlyBest()` → rpc `get_monthly_best`.
  - [x] `@riverpod myMonthlyBest` provider; invalidate alongside `myMotivationStats` (same seams).
- [x] **Task 3 — UI** (AC: 1,2,3,4)
  - [x] `features/motivation/ui/monthly_best.dart`: (a) `PreviousMonthCard` shown only when `showPreviousMonthCard` — "Last month: N · Best: M"; (b) `NewPersonalBestBanner` shown when `isNewBest` and not dismissed this month — "New personal best — N closed this month!", dismiss "×".
  - [x] Dismiss persistence: secure-storage key `monthly_best_dismissed = YYYY-MM` (tenant-month). Banner hidden if dismissed value == current month → "persists until dismissed or end of month".
  - [x] Place both below `PersonalStatsCard` in `home_screen` `_LeadsView`. No employee comparison anywhere (AC-4).
- [x] **Task 4 — Tests**
  - [x] `monthly_best_test.dart`: model parse; `showPreviousMonthCard` boundary (day 7 true, 8 false); `isNewBest` (this>best, this==best false, this=0 false).

### Review Findings (2026-05-28)

- [x] [Review][Patch] **P7** Dismissal key uses device tz not tenant tz → banner can reappear across month boundary or after device-tz change [`apps/mobile/lib/features/motivation/ui/monthly_best.dart` `_currentMonthKey`, `supabase/migrations/0034_get_monthly_best.sql`]
- [x] [Review][Patch] **P12** MonthlyBestSection initState — dismissed banner flashes for 1 frame before secure-storage read completes [`apps/mobile/lib/features/motivation/ui/monthly_best.dart` initState]
- [x] [Review][Defer] **D7** Ties don't trigger new-best (`>` not `>=`) [`monthly_best.dart` isNewBest] — deferred, matches spec wording "beats"

## Dev Notes

- Personal-only, no leaderboards [Source: epics.md#Epic 7 intro, Story 7.4 AC-4].
- Reuse tenant-tz sold-month bucketing from 0030/0031/0032. Per-lead sold month from the latest `status_changed→sold` event; group; max over prior months.
- `all_time_best` excludes the current month so AC-3 "exceeds previous best" is meaningful; first-ever sale (best=0) counts as a new best — acceptable.
- Card placement: stats card (7.1) → previous-month card (7.4) → new-best banner → MY LEADS. Match `_TodayWidget` visual language.
- Dismiss is per-month (secure storage); resets automatically next month since the key compares to the current YYYY-MM.

### References
- [Source: epics.md#Story 7.4] · [architecture.md#L40 tenant-tz] 
- [Source: supabase/migrations/0030_get_my_motivation_stats.sql] — sold-month SQL
- [Source: apps/mobile/lib/features/home/ui/home_screen.dart] — placement
- [Source: apps/mobile/lib/features/motivation/ui/personal_stats_card.dart] — card style

## Dev Agent Record
### Agent Model Used
claude-opus-4-7 (Amelia)
### Debug Log References
- Live verified (real user JWT): `get_monthly_best` → `{this_month_sold:0, last_month_sold:0, all_time_best:0, day_of_month:28}` HTTP 200. Today is the 28th IST → `showPreviousMonthCard=false` (correct, past first week).
- Full mobile suite green (90 tests, +8 new); `flutter analyze` 0 errors.
### Completion Notes List
- **Card placement**: stats card (7.1) → `MonthlyBestSection` (banner + previous-month card) → MY LEADS list. Section returns `SizedBox.shrink` when nothing applicable, so no empty space.
- **Dismiss persistence**: `flutter_secure_storage` key `monthly_best_dismissed = YYYY-MM` keyed off device local time. Single-tenant V1 (IST) → device tz ≈ tenant tz; acceptable. Will re-evaluate when multi-tz tenants land.
- **all_time_best excludes current month** so AC-3 "exceeds prior best" is meaningful. First-ever close (best=0) counts as a new best — explicit + intentional.
- **Invalidation seams**: `myMonthlyBestProvider` is invalidated on home pull-to-refresh and both sold paths (`pending_outcome_sheet` + `edit_lead_sheet`). The banner appears immediately the moment a transition-to-sold pushes `this_month_sold > all_time_best`.
- **No leaderboards / no comparison to other employees** anywhere (AC-4).
- Visual on-device confirmation pending next `flutter run`.
### Change Log
- 2026-05-28: Implemented Story 7.4 — `get_monthly_best` RPC (0034), `MonthlyBest` model + provider, `MonthlyBestSection` UI (previous-month card + dismissible new-best banner), wired into home + sold-path invalidations.
### File List
**New**
- `supabase/migrations/0034_get_monthly_best.sql`
- `apps/mobile/lib/features/motivation/data/models/monthly_best.dart`
- `apps/mobile/lib/features/motivation/ui/monthly_best.dart`
- `apps/mobile/test/features/motivation/monthly_best_test.dart`
**Modified**
- `apps/mobile/lib/features/motivation/data/motivation_repository.dart` — `getMonthlyBest`.
- `apps/mobile/lib/features/motivation/providers/motivation_providers.dart` — `myMonthlyBest` provider (+ generated).
- `apps/mobile/lib/features/home/ui/home_screen.dart` — insert `MonthlyBestSection` sliver + invalidate on refresh.
- `apps/mobile/lib/features/leads/ui/pending_outcome_sheet.dart` — invalidate on sold.
- `apps/mobile/lib/features/leads/ui/edit_lead_sheet.dart` — invalidate on sold.
