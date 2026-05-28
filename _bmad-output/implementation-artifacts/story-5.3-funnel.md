# Story 5.3 — Conversion Funnel Chart

**Epic:** 5 — Admin Analytics  
**Status:** done  
**Started:** 2026-05-28

## Summary

Admin page at `/funnel` showing a visual conversion funnel: Total Leads → Warm → Hot → Visited → Sold, with employee/project/date-range filters and drop-off percentages.

## Acceptance Criteria

- AC1: Five funnel stages visible: Total Leads, Warm, Hot, Visited (visit_date IS NOT NULL AND visit_date < now()), Sold
- AC2: Each stage shows lead count and drop-off % from previous stage (NULL for Total)
- AC3: Filters: All Employees / specific Employee, All Projects / specific Project, All Time / Today / Last 7 days / Last 30 days
- AC4: Filter combinations apply correctly (e.g. Employee X + Project Y + Last 30 days)
- AC5: Date filter applies to leads.created_at AT TIME ZONE tenant_tz

## Implementation Plan

### Backend — Migration 0050

- `get_funnel_stats(p_employee_id, p_project_id, p_days)` RPC
- SECURITY DEFINER, admin-only, tenant-isolated
- Single CTE scan: base_leads → agg (FILTER aggregates) → stages → with_prev (LAG) → RETURN
- dropoff_pct: NULL for total row; ROUND((prev-curr)*100.0/NULLIF(prev,0),1) for others
- REVOKE PUBLIC/anon; GRANT authenticated

### Frontend — apps/admin/src

- `app/(app)/funnel/page.tsx` — server component, searchParams pattern
- `components/funnel/funnel-view.tsx` — client component
  - Filter bar: Employee select, Project select, Date range buttons
  - 4 summary stat cards
  - recharts BarChart layout="vertical" (5 colored bars with custom labels)
  - Drop-off table: Stage | Count | Drop-off % | vs Total %
- `app/(app)/layout.tsx` — add "Funnel" nav link after "Performance"

## Files Created/Modified

- `nirman-crm/supabase/migrations/0050_funnel_stats.sql`
- `nirman-crm/apps/admin/src/app/(app)/funnel/page.tsx`
- `nirman-crm/apps/admin/src/components/funnel/funnel-view.tsx`
- `nirman-crm/apps/admin/src/app/(app)/layout.tsx` (add Funnel nav link only)

## Review Findings

- [x] [Review][Patch] Negative dropoff_pct shows wrong ▼ symbol in chart label [funnel-view.tsx] — fixed: conditional ▼/▲ based on sign
- [x] [Review][Patch] XAxis domain=[0,totalCount] clips bars when stage count > total [funnel-view.tsx] — fixed: domain=[0,'auto']
- [x] [Review][Patch] renderBarLabel renders at left edge when lead_count=0 [funnel-view.tsx] — fixed: return null guard
- [x] [Review][Patch] Table ▼ symbol always shows, red highlight misses negative values [funnel-view.tsx] — fixed: conditional symbol + text-destructive for negative
- [x] [Review][Defer] NULL JWT role check (systemic, pre-existing in all migrations) — deferred, pre-existing
- [x] [Review][Defer] p_days=1 includes yesterday (consistent with 0049 pattern) — deferred, pre-existing

## Definition of Done

- Migration 0050 applied via `supabase db push --linked`
- RPC verified live via execute_sql
- `/funnel` page renders with filters and chart
- All 5 ACs green
- Committed and pushed to main
