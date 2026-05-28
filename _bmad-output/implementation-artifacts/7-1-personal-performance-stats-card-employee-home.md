# Story 7.1: Personal Performance Stats card on Employee home

Status: ready-for-dev

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an Employee,
I want a personal stats card on my home screen showing my Sold this month, follow-up streak, and conversion rate,
so that I can see my own progress without comparing to others.

## Acceptance Criteria

1. **Given** I am on the home screen below the Today's Actions widget (Story 3.8) **When** the stats card loads **Then** I see three values: "Sold this month: N", "Follow-up streak: N days", "Conversion rate: X.X%" (current month, one decimal).
2. "Sold this month" counts my Leads whose most recent `status_changed` event transitioned to `sold` within the current calendar month (tenant timezone).
3. "Follow-up streak" counts consecutive calendar days (tenant timezone, ending today) on which I logged at least one qualifying Action (per Story 3.7 definition); the streak resets to 0 if any day in the run has zero qualifying Actions. If I logged no qualifying action today but did yesterday, today is not yet broken — see Dev Notes "Streak edge cases".
4. "Conversion rate" = (my Sold this month) / (total Leads ever assigned to me), rendered to one decimal as a percentage. When denominator is 0, render `0.0%` (never divide-by-zero / NaN).
5. The card is visible only to me — it reads only the caller's own data via `auth.uid()`; no other Employee's numbers are reachable.
6. Offline / fetch error: the card shows the last-cached values with a "last updated [relative time]" subtitle instead of an error state. On first-ever load with no cache, it shows a skeleton, then zeros if the fetch fails.

## Tasks / Subtasks

- [ ] **Task 1 — Migration: `get_my_motivation_stats()` RPC** (AC: 1,2,3,4,5)
  - [ ] New file `supabase/migrations/0030_get_my_motivation_stats.sql` (next free number — current max is 0029).
  - [ ] `CREATE OR REPLACE FUNCTION public.get_my_motivation_stats()` → `RETURNS TABLE (sold_this_month int, followup_streak_days int, conversion_rate numeric, total_assigned int)`.
  - [ ] `LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions`. Resolve `v_user_id := auth.uid()`; `RAISE EXCEPTION 'not_authenticated'` if null. (Mirror 0029 pattern.)
  - [ ] Resolve tenant timezone: `SELECT timezone FROM public.tenants WHERE id = auth_tenant_id()` into `v_tz` (fallback `'Asia/Kolkata'` if null). All date bucketing uses `(now() AT TIME ZONE v_tz)::date` and `date_trunc('month', now() AT TIME ZONE v_tz)`.
  - [ ] **sold_this_month**: count leads assigned to `v_user_id` whose latest `status_changed` timeline event has `payload->>'to' = 'sold'` (or `leads.status='sold'` with a `status_changed`→sold event this month — see Dev Notes "Sold definition") with `occurred_at` in the current tenant-month.
  - [ ] **total_assigned**: count of all leads ever assigned to `v_user_id` (include dead/sold/archived — "ever assigned"). See Dev Notes on whether reassigned-away leads count.
  - [ ] **conversion_rate**: `round(100.0 * sold_this_month / NULLIF(total_assigned,0), 1)`, coalesced to `0.0`.
  - [ ] **followup_streak_days**: count consecutive tenant-tz calendar days ending today with ≥1 qualifying timeline event by this user. Qualifying event_types = `status_changed, remark_added, followup_rescheduled, call_initiated, whatsapp_sent, visit_rescheduled, archived` [Source: epics.md#Story 3.7]. Implement with a generate_series day walk or gap-detection CTE (see Dev Notes for reference SQL).
  - [ ] `REVOKE EXECUTE ... FROM PUBLIC, anon;` `GRANT EXECUTE ... TO authenticated;` Add `COMMENT ON FUNCTION`.
  - [ ] Apply via `supabase db push --linked` (do NOT use MCP timestamp-named apply — keep file-based history consistent). Verify it appears via `supabase migration list`.
- [ ] **Task 2 — Model + repository** (AC: 1)
  - [ ] Add `MotivationStats` model in `apps/mobile/lib/features/motivation/data/models/motivation_stats.dart`: `int soldThisMonth, int followupStreakDays, double conversionRate, int totalAssigned, DateTime fetchedAt`. Add `fromJson` (guard numeric→double for conversion_rate; Postgres `numeric` arrives as String or num — use `(j['conversion_rate'] as num).toDouble()` with String fallback).
  - [ ] New `MotivationRepository` in `apps/mobile/lib/features/motivation/data/motivation_repository.dart`: `Future<MotivationStats> getMyStats()` calling `_supabase.rpc('get_my_motivation_stats')`, mapping `(result as List).first`. Riverpod `@riverpod MotivationRepository motivationRepository(...)`. Follow `LeadRepository` shape [Source: lead_repository.dart].
- [ ] **Task 3 — Offline cache (Drift)** (AC: 6)
  - [ ] Add a single-row Drift table `MotivationStatsCache` (columns mirror the model + `fetched_at`) in the existing local DB, OR — simpler and acceptable for a 4-int snapshot — cache the JSON via `flutter_secure_storage` under key `motivation_stats_v1`. Pick ONE; document choice. [Architecture prefers Drift for offline reads — L277/L431 — but secure_storage is acceptable for a tiny non-sensitive snapshot; confirm in Dev Agent Record.]
  - [ ] Repository writes cache on every successful fetch; on RPC error, returns the cached snapshot (if any) so the provider resolves to data, not error.
- [ ] **Task 4 — Provider** (AC: 1,6)
  - [ ] `@riverpod Future<MotivationStats> myMotivationStats(...)` in `apps/mobile/lib/features/motivation/providers/motivation_providers.dart`. Invalidate it wherever a status change to sold or a qualifying action is logged (at minimum: after `submitCallOutcome`, `markLeadDead`, `setFollowup`, lead create/edit) so the card stays fresh. Reuse the existing invalidation seams in `lead_detail_screen` / `home_screen`.
- [ ] **Task 5 — UI: stats card** (AC: 1,5,6)
  - [ ] New widget `apps/mobile/lib/features/motivation/ui/personal_stats_card.dart` (`PersonalStatsCard`). Three stat tiles in a row, matching the visual language of `_TodayWidget` / `_CountTile` (surfaceRaised container, borderHairline, AppColors, GoogleFonts headings). Title "MY PROGRESS".
  - [ ] States: skeleton (reuse `_Shimmer` style), data, and cached-with-subtitle ("Updated 3m ago"). No red error state.
  - [ ] Insert into `home_screen.dart` `_LeadsView` as a `SliverToBoxAdapter` immediately AFTER the Today's Actions widget and BEFORE the "MY LEADS" section header (AC-1 placement).
- [ ] **Task 6 — Tests**
  - [ ] `motivation_stats_test.dart`: `fromJson` parses numeric conversion_rate (both String and num forms); divide-by-zero guard yields 0.0.
  - [ ] Widget test: card renders three labelled values from a fixed `MotivationStats`; cached state shows the "Updated …" subtitle.
  - [ ] (If feasible) a pgTAP or manual SQL check of the streak walk on seeded timeline rows — at minimum document a manual verification query in the Dev Agent Record.

## Dev Notes

### Files to touch
- **NEW** `supabase/migrations/0030_get_my_motivation_stats.sql`
- **NEW** `apps/mobile/lib/features/motivation/data/models/motivation_stats.dart` (+ `.g.dart` if json_serializable; project hand-writes `fromJson` elsewhere — match that, no codegen needed for the model)
- **NEW** `apps/mobile/lib/features/motivation/data/motivation_repository.dart` (+ generated `.g.dart` via build_runner — it uses `@riverpod`)
- **NEW** `apps/mobile/lib/features/motivation/providers/motivation_providers.dart` (+ `.g.dart`)
- **NEW** `apps/mobile/lib/features/motivation/ui/personal_stats_card.dart`
- **UPDATE** `apps/mobile/lib/features/home/ui/home_screen.dart` — insert `PersonalStatsCard` sliver after `_TodayWidget` (line ~176). Preserve existing pending-outcome lifecycle logic, mark-dead Dismissible, FAB, skeleton/error views — do not regress them.
- After adding `@riverpod` providers/repository, run `dart run build_runner build --delete-conflicting-outputs` in `apps/mobile`.

### Architecture patterns & constraints
- **Motivation feature lives in `lib/features/motivation/`** [Source: architecture.md#Component-Source-Map (Epic 7) L817; source tree L681-687]. Keep the established `data/ providers/ ui/` sub-structure used by `features/leads`.
- **SECURITY DEFINER RPC** is the canonical read pattern for cross-table aggregates that must bypass RLS safely while scoping to `auth.uid()` [Source: existing 0017_get_my_leads.sql, 0029_get_lead_timeline_fn.sql]. Always `SET search_path` and `REVOKE … FROM PUBLIC, anon; GRANT … TO authenticated`.
- **Timezone-aware date buckets** — "today", "this month", and each streak day MUST be computed in the tenant timezone, never UTC [Source: architecture.md#Key-Decisions L40, L369]. The `tenants` table carries the timezone column — read it; fall back to `'Asia/Kolkata'`. Verify the column name against `0001`/tenants schema before writing the migration.
- **Performance** — home screen budget <1.5s [Source: architecture.md L44]. The RPC is a few indexed aggregates; ensure `lead_timeline(actor_user_id, occurred_at, event_type)` and `leads(assigned_to_user_id, status)` are index-friendly. `last_action_at` is already indexed [L389].
- **Offline tolerance** — Drift is the architecture's local store for offline-tolerant reads [L277, L431]. AC-6 only needs a last-known snapshot + timestamp, so either a 1-row Drift table or a secure_storage JSON blob satisfies it. Do not over-build a sync engine here.

### Sold definition (resolve before coding the migration)
AC-2 says "most recent `status_changed` to Sold in the current calendar month". Two readings:
1. The lead's CURRENT status is `sold` AND the `status_changed→sold` event occurred this tenant-month.
2. Any `status_changed` whose `payload->>'to'='sold'` occurred this month (even if later reverted).
**Use reading (1)** — count leads where `leads.status='sold'` AND there exists a `status_changed` timeline event this tenant-month with `payload->>'to'='sold'`. This avoids counting churned/reverted sales. Confirm the `status_changed` payload shape (`from`/`to` keys) against `log_timeline_event` / 0012 / 0022 before relying on it.

### total_assigned / conversion denominator
AC-4 = "total Leads ever assigned to me". Simplest correct source: count leads where `assigned_to_user_id = v_user_id` now. Reassignment history (Epic 4) is not built yet, so "currently assigned" == "ever assigned" for V1. Note this assumption in the Dev Agent Record; revisit when Story 4.1 reassignment lands (a lead reassigned away would drop out of the denominator).

### Streak edge cases
- Streak = longest run of consecutive tenant-tz days, ending at today, each having ≥1 qualifying event by this user.
- If today has 0 qualifying actions but yesterday had ≥1: the streak is NOT yet broken for "today" — count the run ending yesterday (i.e. start the walk from the most recent day that has activity, but only treat the streak as "current" if that day is today or yesterday). Decide and document: recommended — streak = consecutive days with activity counting back from today; today counts only if it has activity, otherwise count back from yesterday; if the last active day is older than yesterday, streak = 0. This matches Story 7.3's "log a follow-up to keep it going" semantics.
- Reference approach: `SELECT DISTINCT (occurred_at AT TIME ZONE v_tz)::date AS d` for qualifying events by user → walk descending from today/yesterday counting contiguous days.

### Previous-story intelligence
- **Story 3.8** built the Today's Actions widget (`_TodayWidget`, `_CountTile`) — the stats card sits directly below it and should match its tile aesthetic. [Source: home_screen.dart]
- **Story 3.6/3.7** established the qualifying-action event list and tenant-tz cron handling; reuse the SAME event_type list for the streak so the two features agree.
- **Riverpod codegen**: providers use `@riverpod` + generated `.g.dart`. The repository provider returns the concrete repo (see `leadRepository`). Run build_runner after adding files.
- **RPC numeric quirk**: Postgres `numeric` deserializes via supabase_flutter as either `num` or `String` depending on value; the model's `fromJson` must handle both (`num`→toDouble, else `double.parse`).

### Testing standards
- Dart unit + widget tests under `apps/mobile/test/features/motivation/`. Match existing test style (`lead_model_test.dart`). Run `flutter test`.
- `flutter analyze` must stay at 0 errors (warnings tolerated per repo baseline).

### Project Structure Notes
- New top-level mobile feature `motivation/` — first story in Epic 7; aligns with architecture source tree. No conflicts with existing structure.
- Migration numbering continues the file-based sequence (…0029 → 0030). The repo uses file-based migrations reconciled with `supabase migration repair`; avoid MCP `apply_migration` (creates timestamp-named entries that desync history).

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Story 7.1] — ACs, role/benefit
- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.7] — qualifying-action event list, streak definition
- [Source: _bmad-output/planning-artifacts/architecture.md#L40] — tenant-timezone date bucketing
- [Source: _bmad-output/planning-artifacts/architecture.md#L277,L431] — Drift local store / offline reads
- [Source: _bmad-output/planning-artifacts/architecture.md#L681-687,L817] — motivation feature location
- [Source: apps/mobile/lib/features/home/ui/home_screen.dart] — placement + tile visual language (UPDATE target)
- [Source: supabase/migrations/0017_get_my_leads.sql, 0029_get_lead_timeline_fn.sql] — SECURITY DEFINER RPC pattern
- [Source: apps/mobile/lib/features/leads/data/lead_repository.dart] — repository + provider shape

## Dev Agent Record

### Agent Model Used

claude-opus-4-7 (Amelia, bmad-agent-dev)

### Debug Log References

### Completion Notes List

- Story context created 2026-05-28. Comprehensive developer guide; Epic 7 first story. First story in epic → epic-7 moved to in-progress.

### File List
