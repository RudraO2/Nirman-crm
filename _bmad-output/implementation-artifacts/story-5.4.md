# Story 5.4 — Employee Activity Status

**Status:** In Progress  
**Epic:** 5 — Admin Analytics & Reporting  
**Baseline commit:** e4d3a64 (Story 5.3 done, 2026-05-28)

---

## User Story

As an Admin,  
I want to see each Employee's last action timestamp and today's activity counts,  
So that I have a passive pulse on team activity.

---

## Acceptance Criteria

- **AC-1:** Each Employee row shows: last action timestamp, leads updated today, follow-ups completed today.
- **AC-2:** Counts reset at midnight in the tenant timezone.
- **AC-3:** No time-based red/green status (no working hours concept).
- **AC-4:** "Last action" updates within 1 minute of an Employee action (60s client-side auto-refresh via `router.refresh()`).

---

## Technical Spec

### Migration: `supabase/migrations/0051_employee_activity_stats.sql`

One new function `public.get_employee_activity_stats()`:

```sql
RETURNS TABLE (
  employee_id               uuid,
  employee_name             text,
  last_action_at            timestamptz,
  leads_updated_today       int,
  followups_completed_today int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
```

- Admin-only (JWT role check)
- `v_tenant_id` from `auth_tenant_id()`
- `v_tz` from `tenants.timezone` COALESCE `'Asia/Kolkata'`
- `v_today` = `(now() AT TIME ZONE v_tz)::date`
- CTEs:
  - `employees`: active employees (`role='employee'`, `is_active=true`, `tenant_id=v_tenant_id`)
  - `timeline_agg`: JOIN `lead_timeline → leads`, aggregate per employee:
    - `last_action_at = MAX(tl.occurred_at)`
    - `leads_updated_today = COUNT(DISTINCT l.id) FILTER WHERE (tl.occurred_at AT TIME ZONE v_tz)::date = v_today`
  - `followup_today`: COUNT(*) per employee of leads where followup was due today AND a timeline event after `next_followup_at` exists
- Final: LEFT JOIN employees → timeline_agg → followup_today, COALESCE counts to 0, ORDER BY `last_action_at DESC NULLS LAST`
- `REVOKE FROM PUBLIC, anon; GRANT TO authenticated`

### New Files

1. `apps/admin/src/app/(app)/activity/page.tsx` — server component
   - Calls `supabase.rpc('get_employee_activity_stats')`
   - Renders `<ActivityView employees={data} />`

2. `apps/admin/src/components/activity/activity-view.tsx` — client component
   - `'use client'`
   - `useRouter` from `next/navigation`
   - 60s interval calling `router.refresh()`
   - Table: Employee | Last Action | Leads Updated Today | Follow-ups Done Today
   - `timeAgo()` inline helper (no library)
   - NULL last_action_at → "No activity yet" in muted text
   - No color-coding on any column (AC-3)

### Modified Files

1. `apps/admin/src/app/(app)/layout.tsx` — add "Activity" nav link after "Funnel"

### TypeScript Type

```typescript
type ActivityRow = {
  employee_id: string
  employee_name: string
  last_action_at: string | null
  leads_updated_today: number
  followups_completed_today: number
}
```

---

## Dev Notes

- Reuse `createClient()` + `.rpc()` from `leads/page.tsx`
- Reuse shadcn `Table` components from `team/page.tsx`
- Reuse Tailwind card: `rounded-lg border bg-card p-6`
- `router.refresh()` imported from `next/navigation` (Next.js 16.2.6, confirmed)
- NEVER use MCP `apply_migration` — file-based + `supabase db push --linked`
- Mirror story to `nirman-crm/_bmad-output/implementation-artifacts/`
- Live-verify RPC via `mcp__supabase__execute_sql` (project: `vhgruadourflpxuzuxfn`) before marking done
