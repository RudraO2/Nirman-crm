---
baseline_commit: e37425a525a3c25fa9ea037ba54412b02c23b0f9
---
# Story 7.1: Personal Performance Stats card on Employee home

Status: done

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

- [x] **Task 1 — Migration: `get_my_motivation_stats()` RPC** (AC: 1,2,3,4,5)
  - [x] New file `supabase/migrations/0030_get_my_motivation_stats.sql`.
  - [x] `CREATE OR REPLACE FUNCTION public.get_my_motivation_stats()` → `RETURNS TABLE (sold_this_month int, followup_streak_days int, conversion_rate numeric, total_assigned int)`.
  - [x] `LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions`; `auth.uid()` guard with `RAISE EXCEPTION 'not_authenticated'`.
  - [x] Tenant timezone from `tenants.timezone` (fallback `Asia/Kolkata`); all buckets via `now() AT TIME ZONE v_tz`.
  - [x] **sold_this_month**: `leads.status='sold'` AND a `status_changed`→`sold` timeline event this tenant-month (Reading 1).
  - [x] **total_assigned**: count of leads currently == ever assigned to caller (pre-Epic-4).
  - [x] **conversion_rate**: `round(100.0 * sold / NULLIF(total,0), 1)` coalesced to `0.0`.
  - [x] **followup_streak_days**: gaps-and-islands CTE over qualifying timeline events; run ending today or yesterday.
  - [x] `REVOKE … FROM PUBLIC, anon; GRANT … TO authenticated;` + `COMMENT ON FUNCTION`.
  - [x] Applied via `supabase db push --linked`. Verified end-to-end with a real user JWT over REST: returned `{sold:0, streak:1, conversion:0.0, total:1}` HTTP 200.
- [x] **Task 2 — Model + repository** (AC: 1)
  - [x] `MotivationStats` model with robust `fromJson` (num/String conversion_rate, int coercion).
  - [x] `MotivationRepository.getMyStats()` calling `get_my_motivation_stats`; `@riverpod motivationRepository`.
- [x] **Task 3 — Offline cache** (AC: 6)
  - [x] Chose **flutter_secure_storage** (key `motivation_stats_v1`) over Drift — no Drift DB is scaffolded yet, and a 4-int snapshot does not justify one. Documented in Dev Agent Record.
  - [x] Repository writes cache on success; on RPC error returns cached snapshot; rethrows only when no cache exists.
- [x] **Task 4 — Provider** (AC: 1,6)
  - [x] `@riverpod myMotivationStats`. Invalidated in `home_screen` on pull-to-refresh, mark-dead, new-lead, and after the pending-outcome sheet (status→sold path).
- [x] **Task 5 — UI: stats card** (AC: 1,5,6)
  - [x] `PersonalStatsCard` — three tiles ("Sold this month", "Day streak", "Conversion") matching `_TodayWidget`/`_CountTile` language; title "MY PROGRESS".
  - [x] States: skeleton / data / cached-with-"Updated …" subtitle; error renders zeros (no red state).
  - [x] Inserted in `home_screen` `_LeadsView` after Today's Actions, before the "MY LEADS" header.
- [x] **Task 6 — Tests**
  - [x] `motivation_stats_test.dart` — fromJson (num + String + null conversion_rate), int coercion, cache round-trip, zero().
  - [x] `personal_stats_card_test.dart` — renders three labelled values; fresh vs cached "Updated" subtitle.
  - [x] Streak logic verified via inline SQL replication against seeded data + live RPC call (documented in Dev Agent Record).

### Review Findings (2026-05-28)

- [x] [Review][Patch] **P10** MotivationStats fromCacheJson masks corrupt cache as fresh via DateTime.now() fallback; "Updated 20479d ago" possible on zero-row epoch path [`apps/mobile/lib/features/motivation/data/models/motivation_stats.dart`, `apps/mobile/lib/features/motivation/ui/personal_stats_card.dart` _subtitle]
- [x] [Review][Defer] **D1** Read RPC missing `tenant_id = auth_tenant_id()` filter (consistency with restore_lead) [`supabase/migrations/0030_get_my_motivation_stats.sql`] — deferred, safe under single-tenant V1
- [x] [Review][Defer] **D4** AC-1 label drift — tile labels "Day streak" / "Conversion" vs spec "Follow-up streak: N days" / "Conversion rate: X.X%" [`personal_stats_card.dart`] — deferred, product call on tile vs single-line layout
- [x] [Review][Defer] **D9** Error swallowing in repository helpers obscures auth/RLS denials [`motivation_repository.dart`] — deferred, broader logging-hardening pass

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

- RPC verified live (real user JWT, REST): `POST /rest/v1/rpc/get_my_motivation_stats` → `[{"sold_this_month":0,"followup_streak_days":1,"conversion_rate":0.0,"total_assigned":1}]` HTTP 200.
- Full mobile suite: 75 passing, 0 failing. `flutter analyze`: 0 errors.

### Completion Notes List

- Story context created 2026-05-28; implemented same day. Epic 7 first story → epic-7 in-progress.
- **Sold definition**: Reading (1) — current status `sold` AND a `status_changed→sold` event in the tenant-month. Avoids counting reverted sales.
- **total_assigned assumption**: pre-Epic-4 there is no reassignment history, so "currently assigned" == "ever assigned". Revisit when Story 4.1 lands (a lead reassigned away would leave the denominator).
- **Offline cache**: used `flutter_secure_storage` (not Drift). No Drift DB exists in the app yet; a 4-int snapshot does not warrant scaffolding one. AC-6 satisfied: cached snapshot returned on RPC failure; card shows "Updated …" subtitle when the snapshot is not fresh; zeros shown only when there is no cache at all.
- **Streak**: gaps-and-islands SQL; counts the contiguous run ending today, or yesterday if today has no qualifying action yet (matches Story 7.3 "keep it going" semantics).
- **Fixed a pre-existing failing test** (not introduced by this story): `lead_repository_error_test.dart` mirror of `_throwFromEdgeError` used an unsafe `as Map<String,dynamic>` cast that threw `TypeError` on an empty `{}` literal; synced it to the production `Map<String,dynamic>.from(...)` form. This was a latent failure from the earlier Epic-2/3 merge.
- **Not verified on physical device** — code + server verified; on-device visual check of the card pending next `flutter run` (USB).

### Change Log

- 2026-05-28: Implemented Story 7.1 — `get_my_motivation_stats` RPC (0030), `features/motivation/` module (model, repository w/ secure-storage cache, provider, `PersonalStatsCard`), wired into home screen with stats invalidation. Added motivation unit + widget tests. Fixed pre-existing `lead_repository_error_test` cast bug.

### File List

**New**
- `supabase/migrations/0030_get_my_motivation_stats.sql`
- `apps/mobile/lib/features/motivation/data/models/motivation_stats.dart`
- `apps/mobile/lib/features/motivation/data/motivation_repository.dart` (+ generated `motivation_repository.g.dart`)
- `apps/mobile/lib/features/motivation/providers/motivation_providers.dart` (+ generated `motivation_providers.g.dart`)
- `apps/mobile/lib/features/motivation/ui/personal_stats_card.dart`
- `apps/mobile/test/features/motivation/motivation_stats_test.dart`
- `apps/mobile/test/features/motivation/personal_stats_card_test.dart`

**Modified**
- `apps/mobile/lib/features/home/ui/home_screen.dart` — inserted `PersonalStatsCard` sliver; invalidate `myMotivationStatsProvider` on refresh / mark-dead / new-lead / pending-outcome.
- `apps/mobile/test/features/leads/lead_repository_error_test.dart` — synced `_throwFromEdgeError` mirror to production (cast fix).
