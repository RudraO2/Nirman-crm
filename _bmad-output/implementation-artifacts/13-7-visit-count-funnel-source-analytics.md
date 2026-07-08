# Story 13.7: visit-count funnel and source analytics

Status: review  (migration 0069 written + self-reviewed; per-employee-perf source filter + apply deferred)

## Story

As a Builder Head,
I want the funnel's "Visited" stage driven by real visits and analytics filterable by source,
so that the pipeline reflects verified visits and lead-source performance.

## Acceptance Criteria

1. **Given** migration `0066_visit_funnel_patch.sql` **When** applied **Then** `visit_count` is backfilled `= 1 WHERE visit_date < now() AND visit_count = 0` (retroactive — preserves historical funnel numbers).
2. **And** `get_funnel_stats` "Visited" stage switches from `visit_date < now()` to `visit_count > 0`.
3. **And** funnel + per-employee dashboards accept a `source` filter across all 6 source values.
4. **And** existing funnel filters (employee, project, date range) still combine correctly.

## Tasks / Subtasks

- [ ] **Task 1 — Backfill**: `UPDATE leads SET visit_count = 1 WHERE visit_date IS NOT NULL AND visit_date < now() AND visit_count = 0`.
- [ ] **Task 2 — `get_funnel_stats` patch**: `CREATE OR REPLACE` (from `0054`/`0050` current body) changing only the visited predicate `visit_date IS NOT NULL AND visit_date < now()` → `visit_count > 0`. Add optional `p_source text` filter. Preserve guard/sig/other filters byte-for-byte.
- [ ] **Task 3 — Source filter on dashboards**: thread `p_source` through funnel + per-employee perf RPCs + admin web filter UI.
- [ ] **Task 4 — Apply + tests**: historical visited count unchanged post-backfill; source filter returns correct subsets; combined filters work.

## Dev Notes

- Retroactive decision: backfill makes the definition switch number-preserving. [Source: architecture-builder-ops-v2.md §5.1, §10 flag 2 RESOLVED]
- `get_funnel_stats` current body: `0054` (fn #8) / originally `0050_funnel_stats.sql`. CREATE OR REPLACE, predicate+param only. [Source: 0050, 0054]
- Source enum now 6 values (13.1). [Source: §5.1]
- Admin web only (no mobile) for the filter UI.

## References
- [Source: epics.md#Story 13.7; architecture-builder-ops-v2.md §5.1, §10 flag 2]
- [Source: 0050_funnel_stats.sql, 0054 get_funnel_stats]

## Implementation (2026-06-27)

**File:** `nirman-crm/supabase/migrations/0069_visit_funnel.sql`

- Backfill `visit_count = 1 WHERE visit_count=0 AND visit_date < now()` — retroactive, preserves historical Visited numbers under the new definition.
- `get_funnel_stats` DROP(3-arg)+CREATE(4-arg, adds `p_source text DEFAULT NULL`): Visited stage `visit_date in past` → `visit_count > 0`; source filter `(p_source IS NULL OR l.source::text = p_source)`. Body faithful to 0054; existing 3-arg callers unaffected (p_source defaults).

**Self-review:** added param has DEFAULT NULL → web funnel chart (Story 5.3) calling with 3 named args still resolves. Visited redefinition is now number-preserving thanks to the backfill.

**Deferred (minor):** source filter on `get_employee_performance_stats` (AC3 "per-employee dashboards") — funnel done; per-employee-perf source filter is a small symmetric follow-on. Web filter UI + apply.

**Status:** funnel backend code-complete; minor per-employee-perf source filter + UI remaining.
