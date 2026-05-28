# Story 5.1: 3-Metric Builder Home with Reference Points

**Epic:** 5 — Builder Analytics & Dashboard
**Status:** in-progress
**Stack:** apps/admin (Next.js) + Supabase migration

---

## User Story

As a Builder,
I want my admin home to show exactly three numbers — Leads added today, Follow-ups missed today, Sold this month — each with a reference comparison,
So that I can read the health of my business in 3 seconds.

---

## Acceptance Criteria

**AC-1:** Admin home (/) shows 3 metric cards in a responsive grid.

**AC-2:** "Leads Today" card
- Value: COUNT of leads with `created_at` falling on today's date in tenant timezone
- Reference: yesterday's count ("vs N yesterday")
- Click → navigates to `/leads`

**AC-3:** "Follow-ups Missed" card
- Value: COUNT DISTINCT leads where `(next_followup_at AT TIME ZONE tz)::date = today` AND `next_followup_at < now()` AND NOT EXISTS any `lead_timeline` row with `occurred_at >= next_followup_at`
- Reference: yesterday's missed count using same logic ("vs N yesterday")
- Click → navigates to `/leads`

**AC-4:** "Sold This Month" card
- Value: COUNT DISTINCT leads where `status = 'sold'` AND a `status_changed`→`sold` timeline event occurred in current calendar month (tenant tz)
- Reference: previous calendar month count ("vs N last month")
- Click → navigates to `/leads?status=sold`

**AC-5:** On the 1st of each month at 00:00 tenant time: "Sold this month" shows 0; reference still shows last month's total.

**AC-6:** Error state: single `<p className="text-destructive">` if RPC fails.

---

## Dev Notes

### Migration: `0048_get_builder_home_metrics.sql`

New RPC `public.get_builder_home_metrics()`:
- RETURNS TABLE (leads_today int, leads_yesterday int, followups_missed_today int, followups_missed_yesterday int, sold_this_month int, sold_last_month int)
- SECURITY DEFINER; search_path = public, extensions
- Admin-only guard: `(auth.jwt()->'app_metadata'->>'role') <> 'admin'` → RAISE EXCEPTION
- Tenant tz from `public.tenants` via `auth_tenant_id()`
- Date vars: v_today, v_yesterday, v_month_start, v_last_month_start
- Sold pattern from 0030 (tenant-wide, not per-user scoped)
- Missed followup logic: broad NOT EXISTS (any timeline row with occurred_at >= next_followup_at)

### Page: `apps/admin/src/app/(app)/page.tsx`

- Server component (async function)
- `await createClient()` → `supabase.rpc('get_builder_home_metrics')`
- 3 cards via `<Link>` wrapper + div with `rounded-lg border bg-card p-6` pattern (no card.tsx exists)
- Layout: `grid grid-cols-1 gap-4 sm:grid-cols-3`
- DO NOT modify layout.tsx

### Infrastructure (already in place — do not redo)

- `tenants.timezone` (text, DEFAULT 'Asia/Kolkata')
- `leads.next_followup_at` (timestamptz, nullable, indexed)
- `leads.status` lead_status enum including 'sold'
- `lead_timeline.event_type = 'status_changed'`, `payload->>'to'`
- `auth_tenant_id()` helper function

---

## Tasks

- [x] T1: Write migration 0048_get_builder_home_metrics.sql
- [x] T2: Apply migration via `supabase db push --linked`
- [x] T3: Live-verify RPC via execute_sql
- [x] T4: Write apps/admin/src/app/(app)/page.tsx
- [x] T5: Code review + apply patches
- [x] T6: Commit + push to main
- [x] T7: Mirror story to nirman-crm/_bmad-output/
