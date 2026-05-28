# Story 4.6: Future Pool view and project-match trigger

**Status:** done
**Sprint:** Epic 4
**Baseline commit:** 54da2a3

## Story

As an Admin,
I want a Future Pool view filtered by Interest Type and an automatic banner when a new Project matches existing Future Leads,
So that I can reactivate the right Leads when a new Project launches.

## Acceptance Criteria

- AC1: Future Pool page shows all leads with `status='future'`, filterable by Interest Type via URL query param `?interestType=`
- AC2: Each row: Lead name, Employee (assignee_username), Interest Type, Days since created_at
- AC3: Filter chips for each distinct interest_type present in the loaded leads
- AC4: Creating a Project with `property_type` set → system calls `get_future_pool_match_count`
- AC5: If count > 0 → navigate to `/future-pool?projectMatch=<id>&matchCount=<n>&interestType=<type>`
- AC6: Banner "N Future Leads match this new Project. Review and reactivate?" (dismissable)
- AC7: "Review" button in banner → opens ReactivateDialog with all interest-type-filtered leads pre-loaded
- AC8: "Reactivate selected" button → opens ReactivateDialog with selected rows
- AC9: ReactivateDialog shows lead list with per-lead employee picker
- AC10: "Reactivate & Assign" enabled only when all leads have an assignee
- AC11: On confirm → `reactivate_future_leads` RPC called; timeline records `status_changed` (future→warm, `restored:true`) and `assigned`/`reassigned` events per lead
- AC12: Nav links "Future Pool" and "Projects" added to layout after "Team"
- AC13: Projects page lists all tenant projects with CRUD (insert/inline-edit)

## Technical Spec

### Migration 0046

**File:** `supabase/migrations/0046_story_4_6_future_pool.sql`

1. `ALTER TABLE public.projects ADD COLUMN property_type text NULL`
2. `list_assignable_leads` updated to return `interest_type text` (additive, no breaking change)
3. `reactivate_future_leads(p_leads jsonb) RETURNS jsonb` — admin-only SECURITY DEFINER
4. `get_future_pool_match_count(p_property_type text) RETURNS int` — admin-only SECURITY DEFINER

### New Files

- `apps/admin/src/app/(app)/future-pool/page.tsx` — server component
- `apps/admin/src/app/(app)/future-pool/future-pool-view.tsx` — client component
- `apps/admin/src/components/leads/reactivate-dialog.tsx` — client component
- `apps/admin/src/app/(app)/projects/page.tsx` — server component
- `apps/admin/src/app/(app)/projects/projects-client.tsx` — client component

### Modified Files

- `apps/admin/src/app/(app)/layout.tsx` — add Future Pool + Projects nav links

### RPC Reuse

- `list_assignable_leads(p_status='future', p_include_archived=true, p_limit=200)` — future pool data
- `list_employees_for_assignment()` — employee picker data
- `assign_lead` — called INSIDE `reactivate_future_leads`, not from UI directly

### Property Types

Flat | Plot | Villa | Commercial | Studio | Penthouse (raw strings, no enum)

## Tasks

- [x] Write story spec
- [x] Write migration 0046
- [x] Apply migration via `supabase db push --linked`
- [x] Implement layout.tsx nav links
- [x] Implement future-pool/page.tsx
- [x] Implement future-pool/future-pool-view.tsx
- [x] Implement reactivate-dialog.tsx
- [x] Implement projects/page.tsx
- [x] Implement projects/projects-client.tsx
- [x] Live-verify RPCs via MCP execute_sql
- [x] Run code review on diff vs 54da2a3
- [x] Apply patches; defer remainder
- [x] Update sprint-status.yaml
- [ ] Commit + push to main

### Review Findings

- [x] [Review][Patch] reactivate_future_leads missing auth.uid() null check (P1) [0047_patch_reactivate_future_leads.sql]
- [x] [Review][Patch] reactivate_future_leads employee_id null guard missing (P1) [0047_patch_reactivate_future_leads.sql]
- [x] [Review][Patch] Filter chip links strip projectMatch/matchCount — banner lost after chip click (P1) [future-pool-view.tsx]
- [x] [Review][Patch] Banner stays visible after successful reactivation (P1/P2) [future-pool-view.tsx]
- [x] [Review][Patch] router.refresh() missing before redirect in NewProjectForm (P2) [projects-client.tsx]
- [x] [Review][Patch] openDialogWith called with empty array — empty dialog dead-end (P2) [future-pool-view.tsx]
- [x] [Review][Patch] projectId not encodeURIComponent'd in redirect URL (P3) [projects-client.tsx]
- [x] [Review][Patch] Unused PROPERTY_TYPES constant (P3) [future-pool-view.tsx]
- [x] [Review][Defer] toggleAll clears entire selectedIds — theoretical (nav resets state) [future-pool-view.tsx] — deferred
- [x] [Review][Defer] Error messages leak lead UUID in RAISE EXCEPTION — deferred
- [x] [Review][Defer] assign_lead nulls assignment_deadline on reactivate — future leads have no deadlines by convention — deferred
- [x] [Review][Defer] Column header "Days in Future" vs spec "days since marked Future" — deferred
- [x] [Review][Defer] matchCount URL param not server-re-verified on page load — UI-only — deferred
- [x] [Review][Defer] list_assignable_leads backslash escape fragility — pre-existing — deferred
- [x] [Review][Defer] phone_encrypted null guard missing — pre-existing — deferred
