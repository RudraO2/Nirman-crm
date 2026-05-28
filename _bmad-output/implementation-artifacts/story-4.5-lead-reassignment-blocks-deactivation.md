# Story 4.5 — Lead Reassignment Blocks Employee Deactivation Until Cleared

**Epic:** 4 — Admin Lead Management  
**Status:** in-progress  
**Created:** 2026-05-28  

---

## User Story

As an Admin, I want to be blocked from deactivating an Employee until I have reassigned all their active Leads, so that no Lead becomes orphaned on offboarding.

---

## Acceptance Criteria

| ID | Criterion |
|----|-----------|
| AC-1 | Employee with N > 0 active (non-Archived) leads → Deactivate click opens blocking modal (does NOT call manage-employee) |
| AC-2 | Modal lists all active leads (status ∈ hot/warm/cold) with name, phone_last4, status pill per row |
| AC-3 | Each lead row has an inline employee picker (ComboBox); picker fetches employees via `list_employees_for_assignment()` once on mount |
| AC-4 | "Reassign & Deactivate" button disabled until every lead has an assignee selected |
| AC-5 | On confirm: calls `assign_lead(lead_id, selected_employee_id)` for each lead in sequence |
| AC-6 | After all reassignments succeed: calls `manage-employee(action: 'deactivate', targetUserId: employeeId)` |
| AC-7 | On success: `onSuccess()` callback fires → `router.refresh()` |
| AC-8 | If any `assign_lead` call fails: shows inline error, stops, does NOT deactivate |
| AC-9 | Employee with 0 active leads → Deactivate clicks straight through (existing path, no modal) |
| AC-10 | Deactivated employee's Archived leads (dead/sold/future) retain original ownership — no migration needed |
| AC-11 | Employee editing a lead at moment of reassignment → `LeadReassignedError` thrown → SnackBar "This lead was just reassigned. Refreshing." → sheet pops → providers invalidated |

---

## Technical Design

### Migration 0045 — `supabase/migrations/0045_get_employee_active_lead_count.sql`

**`get_employee_active_lead_count(p_employee_id uuid) RETURNS int`:**
- SECURITY DEFINER; SET search_path = public, extensions
- Admin-only: `(auth.jwt() -> 'app_metadata') ->> 'role' = 'admin'`
- Validates: `p_employee_id` belongs to caller's tenant AND `role = 'employee'`
- Returns: `COUNT(*) FROM leads WHERE assigned_to_user_id = p_employee_id AND tenant_id = v_tenant_id AND status NOT IN ('dead', 'sold', 'future')`
- REVOKE EXECUTE FROM PUBLIC, anon; GRANT to authenticated

### Admin UI — `apps/admin/src/`

**Modify `components/auth/employee-actions.tsx`:**
- On Deactivate click: call `supabase.rpc('get_employee_active_lead_count', { p_employee_id: employeeId })`
- If count > 0: set `showBlockedDialog = true` (do NOT call manage-employee)
- If count = 0: proceed via existing `manage-employee` deactivate path
- Loading state covers the count fetch; error renders as `text-destructive` paragraph

**New `components/auth/deactivation-blocked-dialog.tsx`:**
- Props: `{ employeeId: string; employeeName: string; open: boolean; onOpenChange: (v: boolean) => void; onSuccess: () => void }`
- On mount / open: fetch leads via `list_assignable_leads({ p_employee: employeeId, p_limit: 200 })` (status hot/warm/cold only — default `p_include_archived: false`)
- Fetch employees via `list_employees_for_assignment()` once on mount
- State: `assignments: Record<string, string>` — map lead_id → selected employee_id
- Lead table: name / `•••{phone_last4}` / `<StatusPill status={...} />` / inline employee ComboBox per row
- "Reassign & Deactivate" disabled unless `Object.keys(assignments).length === leads.length && leads.length > 0`
- On confirm:
  1. Sequential: `for (const lead of leads)` → `supabase.rpc('assign_lead', { p_lead_id: lead.id, p_target_user_id: assignments[lead.id] })`
  2. On RPC error: set inline error, return early — do NOT call manage-employee
  3. `supabase.functions.invoke('manage-employee', { body: { action: 'deactivate', targetUserId: employeeId } })`
  4. On success: `onSuccess()` (parent calls `router.refresh()`)
- Loading states: `fetchingLeads`, `submitting` — spinner or disabled button
- Error state: string rendered as `<p className="text-destructive text-sm">{error}</p>`
- Dialog pattern: shadcn `Dialog` + `DialogContent` + `DialogHeader` + `DialogFooter`
- ComboBox pattern: exact `Popover` + `Command` from `assign-dialog.tsx`

### Mobile Flutter — `apps/mobile/`

**`lib/features/leads/data/lead_repository.dart`:**
- Add `LeadReassignedError` exception class (mirrors `DuplicateLeadError` pattern)
- In `updateLead()`: catch `FunctionException` where details.error.code ∈ `['permission_denied', 'lead_not_found_or_not_owner']` → throw `LeadReassignedError`

**`lib/features/leads/ui/edit_lead_sheet.dart`:**
- In `_save()`: add `on LeadReassignedError` catch before generic catch
- Show SnackBar: "This lead was just reassigned. Refreshing."
- Pop sheet: `Navigator.of(context).pop()`
- Invalidate: `ref.invalidate(leadByIdProvider(widget.lead.id))` + `ref.invalidate(myLeadsProvider)`

---

## File Checklist

- [ ] `supabase/migrations/0045_get_employee_active_lead_count.sql`
- [ ] `apps/admin/src/components/auth/employee-actions.tsx` (modified)
- [ ] `apps/admin/src/components/auth/deactivation-blocked-dialog.tsx` (new)
- [ ] `apps/mobile/lib/features/leads/data/lead_repository.dart` (modified)
- [ ] `apps/mobile/lib/features/leads/ui/edit_lead_sheet.dart` (modified)

---

## Out of Scope

- No mobile UI for the blocking modal (admin-only flow)
- No changes to Archived lead ownership (historical attribution preserved by default)
- No new migrations for lead ownership history
