# Story 5.2: Per-Employee Performance Dashboard with Charts

**Epic:** 5 — Builder Analytics
**Status:** in-progress
**Date:** 2026-05-28
**Baseline commit:** 7ea035a (Story 5.1 done)

---

## User Story

As an Admin,
I want a per-Employee performance view with key metrics and charts,
So that I can compare team members and spot performance patterns.

---

## Acceptance Criteria

**AC-1 — Employee table**
- Row per active employee: Name, Active Leads, Warm, Cold, Hot counts
- Followups Completed (p_days window), Followups Missed (p_days window)
- Conversion Rate = ROUND(100 * sold_this_month / total_assigned, 1) — current calendar month, tenant tz
- Toggle button shows/hides Dead, Sold, Future columns (client-side state, no refetch)
- Sortable by Active Leads column (client-side sort, no refetch)
- Clicking a row navigates to `/leads?employee={employee_id}`

**AC-2 — 14-day bar chart**
- Always last 14 calendar days in tenant tz
- 2 bars per day: new_leads + status_changes
- X-axis: MM/DD day labels; legend shown
- NOT affected by date range filter

**AC-3 — Status donut chart**
- Current lead status distribution (all non-archived leads)
- Default shows: Warm (amber), Cold (blue), Hot (red)
- Toggle adds/removes: Dead (gray), Sold (green), Future (purple)
- Toggle is client-side state only — no refetch

**AC-4 — Date range filter**
- Buttons: Today | Last 7 days | Last 30 days
- Clicking navigates via `router.push('/performance?range=N')`
- Filter affects ONLY the table (re-fetches with different p_days)
- Charts remain static

**AC-5 — Performance**
- Page loads ≤ 3 seconds for 50 employees + 10,000 leads

**AC-6 — Custom range deferred**
- Custom date range picker → deferred to deferred-work.md

---

## Technical Spec

### Backend — Migration 0049 (ONE file, three functions)

#### 1. `get_employee_performance_stats(p_days int DEFAULT 30)`

```sql
RETURNS TABLE (
  employee_id         uuid,
  employee_name       text,   -- email_or_username
  active_leads        int,    -- status NOT IN ('dead','sold','future')
  warm_count          int,
  cold_count          int,
  hot_count           int,
  dead_count          int,
  sold_count          int,
  future_count        int,
  followups_completed int,    -- p_days window, see definition below
  followups_missed    int,    -- p_days window, see definition below
  total_assigned      int,    -- all leads ever assigned (no status filter)
  conversion_rate     numeric -- ROUND(100*sold_this_month/total_assigned, 1)
)
```

- `SECURITY DEFINER`, `search_path = public, extensions`, admin-only
- Only `role='employee' AND is_active=true`
- **followups_completed**: leads where `(next_followup_at AT TZ v_tz)::date` is in `[v_today - p_days, v_today]` AND EXISTS timeline event `occurred_at >= next_followup_at`
- **followups_missed**: same window AND `next_followup_at < now()` AND NOT EXISTS such timeline event
- **sold_this_month**: leads with `status='sold'` AND status_changed→'sold' timeline event in current tenant-tz calendar month
- Uses CTEs for clean aggregation, no cross-join fan-out

#### 2. `get_pipeline_activity_14d()`

```
RETURNS TABLE (day date, new_leads int, status_changes int)
```

- Always last 14 days (v_today - 13 → v_today) in tenant tz
- `generate_series` zero-fills missing days
- `new_leads`: created_at bucketed to tenant tz
- `status_changes`: lead_timeline event_type='status_changed' bucketed to tenant tz

#### 3. `get_lead_status_distribution()`

```
RETURNS TABLE (status text, lead_count int)
```

- All 6 statuses always returned (LEFT JOIN on value list)
- Zero-fill: counts 0 if no leads in that status

All three: `REVOKE FROM PUBLIC, anon; GRANT TO authenticated`

### Frontend — apps/admin/src

#### Page: `app/(app)/performance/page.tsx`
- Server component
- `searchParams: Promise<Record<string, string | string[] | undefined>>`
- `range` param → `p_days`: `'1'→1`, `'7'→7`, else `30`
- `Promise.all` three RPCs
- Any error → `<p className="text-destructive">...</p>`
- Renders `<PerformanceDashboard>` with all data + `initialRange`

#### Component: `components/performance/performance-dashboard.tsx`
- `'use client'`
- Recharts: `BarChart` (dual bars) + `PieChart` with `innerRadius` (donut)
- Date filter: 3 buttons, active state with `bg-primary text-primary-foreground`
- Table: client-sort by active_leads, row click → `/leads?employee=id`
- Status toggle: client state only
- Layout: Tailwind + shadcn tokens (`bg-card`, `border`, `rounded-lg`, etc.)

#### Nav: `app/(app)/layout.tsx`
- Add `<Link href="/performance">Performance</Link>` after Future Pool link

### Types (inline in component files)

```ts
type EmployeeStat = {
  employee_id: string; employee_name: string;
  active_leads: number; warm_count: number; cold_count: number;
  hot_count: number; dead_count: number; sold_count: number;
  future_count: number; followups_completed: number;
  followups_missed: number; total_assigned: number;
  conversion_rate: number
}
type ChartDay = { day: string; new_leads: number; status_changes: number }
type StatusDist = { status: string; lead_count: number }
```

---

## Deferred

- Custom date range picker (needs date-fns or similar — not installed)
  → `nirman-crm/deferred-work.md`

---

## Files Changed

| File | Action |
|------|--------|
| `nirman-crm/supabase/migrations/0049_performance_dashboard.sql` | CREATE |
| `nirman-crm/apps/admin/src/app/(app)/performance/page.tsx` | CREATE |
| `nirman-crm/apps/admin/src/components/performance/performance-dashboard.tsx` | CREATE |
| `nirman-crm/apps/admin/src/app/(app)/layout.tsx` | MODIFY (Performance link) |
| `nirman-crm/apps/admin/package.json` | MODIFY (recharts dep) |
| `nirman-crm/deferred-work.md` | MODIFY (custom range defer) |
