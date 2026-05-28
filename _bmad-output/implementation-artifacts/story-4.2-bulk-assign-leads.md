# Story 4.2 — Admin Bulk-Assigns Leads with Equal Distribution

**Status:** in-progress  
**Epic:** 4 — Admin Lead Management  
**Baseline commit:** e6ee70a (Story 4.1 shipped 2026-05-28)  
**Stack:** Next.js 16.2.6 · React 19 · @supabase/ssr · Tailwind v4 · shadcn/radix-ui · @dnd-kit/core

---

## Acceptance Criteria (from epics.md lines 668-684)

| ID | Given | When | Then |
|----|-------|------|------|
| AC1 | N leads selected | "Distribute Equally" mode, M employees chosen | Leads assigned round-robin across M employees |
| AC2 | Distribute mode confirmed | — | Each employee gets ONE push notification listing count of new leads |
| AC3 | Any assignment | — | Each lead's Timeline records `assigned` (or `reassigned`) event |
| AC4 | "Manual Allocation" mode selected | Admin drags leads into employee buckets | Allocation per bucket is used on confirm |
| AC5 | Any employee has >80 active leads after allocation | Before confirm | Warning banner shown per employee |

---

## Technical Design

### Why @dnd-kit/core, not react-aria

Radix UI (our primitive library) ships no DnD primitive. Candidates evaluated:

- **`@dnd-kit/core`** — 25k+ stars, Pointer Events API, React 19 compatible, no imposed DOM structure, integrates naturally with Tailwind. Composable `useDraggable` + `useDroppable` hooks fit our "drag lead card → drop into employee bucket" model exactly.
- **`react-aria`** — excellent a11y but requires adopting its full component model; conflicts with existing shadcn/radix-ui primitives; overkill for an admin-only desktop tool.
- **`hello-pangea/dnd`** — designed for sorted lists (vertical/horizontal); our use case is arbitrary bucket-drop with no within-bucket ordering needed.
- **`react-beautiful-dnd`** — deprecated.

**Decision: `@dnd-kit/core` + `@dnd-kit/utilities`.**

### Architecture

```
leads/page.tsx (RSC)
  ├── fetches leads + employees via RPC (unchanged)
  └── <LeadsTable leads={…} employees={…} />  ← new Client Component boundary

LeadsTable (client)
  ├── manages selectedIds: Set<string>
  ├── renders per-row checkboxes + existing AssignDialog
  └── when selectedIds.size > 0: shows <BulkAssignDialog …/>

BulkAssignDialog (client, multi-step)
  ├── Step 1: Employee multi-select + deadline + mode toggle
  ├── Step 2a (Distribute): Preview table + warning banner
  └── Step 2b (Manual): @dnd-kit DnD canvas + warning banner
```

### Migration 0040 — Two new RPCs

#### `bulk_assign_leads(p_assignments jsonb, p_deadline timestamptz)`
- `p_assignments`: `[{"lead_id":"uuid","target_user_id":"uuid"}]`
- Admin-only (SECURITY DEFINER), max 500 items guard
- Loops through assignments, calls `public.assign_lead()` for each pair
  — reuses all validation + timeline + cascade-share-revoke logic from 0038/0039
- Returns `jsonb`: `{assigned: int, per_employee: {"<user_id>": count, …}}`

#### `get_employee_active_lead_counts(p_user_ids uuid[])`
- Admin-only (SECURITY DEFINER)
- Returns `TABLE(user_id uuid, active_count bigint)` of active (hot/warm/cold) lead counts for the given employees
- Used by UI to populate warning banner before confirm

### Edge Function: `send-bulk-assignment-notification`

Separate from Story 4.1's `send-assignment-notification` (which sends per-lead messages).

Body: `{ assignments: [{ user_id: string, count: number }] }`

Logic per employee:
- Fetch device_tokens for user
- Build message: `"${count} new ${count === 1 ? 'lead' : 'leads'} assigned"`
- Send ONE FCM notification per token
- Delete stale tokens on failure (same pattern as 4.1)

Returns: `{ sent: number }` (total FCM sends, not employees).

### UI Components

#### `LeadsTable` (`components/leads/leads-table.tsx`)
- `'use client'` — manages `selectedIds: Set<string>` via `useState`
- Header checkbox: select-all / deselect-all
- Row checkboxes: toggle individual lead
- "Bulk Assign (N)" button appears when `selectedIds.size >= 2`
- Passes selection to `BulkAssignDialog`

#### `BulkAssignDialog` (`components/leads/bulk-assign-dialog.tsx`)
- `'use client'` — complex local state machine

**Step 1 — Configure:**
- Multi-select employees via Command/Popover (checklist style, min 1 required)
- `datetime-local` deadline input (optional, same as AssignDialog)
- Mode toggle: `Distribute Equally` (default) | `Manual Allocation`
- "Preview" button → Step 2

**Step 2a — Distribute Preview:**
- Table: Employee | New Leads Count | Lead names (up to 3 shown, "+ N more")
- Round-robin computed client-side: `leads[i % employees.length]`
- Loads existing active counts via `get_employee_active_lead_counts` on mount
- Warning banner (amber) per employee where `existing + new > 80`
- Buttons: "Back" | "Confirm Assignment"

**Step 2b — Manual Allocation (DnD):**
- `DndContext` from `@dnd-kit/core` with `closestCenter` collision detection
- Left panel: "Unassigned" droppable pool of lead cards
- Right panel: one droppable bucket per selected employee
- `DragOverlay` renders a ghost card during drag
- Lead card shows: name, `•••XXXX` phone, StatusPill
- Warning badge on employee bucket header: "⚠ X active — will exceed 80" (amber)
- "Distribute Equally" reset button (re-runs round-robin on current state)
- Buttons: "Back" | "Confirm (N assigned)" — disabled if any lead still in Unassigned pool

**Confirm flow (both modes):**
1. Build `p_assignments` array from allocation state
2. `supabase.rpc('bulk_assign_leads', { p_assignments, p_deadline })`
3. On success: fire-and-forget `send-bulk-assignment-notification` per employee (grouped)
4. `toast.success("N leads assigned to M employees")`
5. `router.refresh()` + close dialog + clear selection

**Error handling:**
- `permission_denied` → "You do not have permission."
- `lead_not_found` / `target_not_assignable` → "Some leads or employees are no longer valid. Refresh and retry."
- Generic → show raw message

---

## File Manifest

| Action | Path |
|--------|------|
| CREATE | `nirman-crm/supabase/migrations/0040_bulk_assign_leads_rpc.sql` |
| CREATE | `nirman-crm/supabase/functions/send-bulk-assignment-notification/index.ts` |
| CREATE | `nirman-crm/apps/admin/src/components/leads/leads-table.tsx` |
| CREATE | `nirman-crm/apps/admin/src/components/leads/bulk-assign-dialog.tsx` |
| MODIFY | `nirman-crm/apps/admin/src/app/(app)/leads/page.tsx` |

---

## Verification Plan (live SQL via mcp__supabase__execute_sql)

Test users from CLAUDE.md:
- admin: `e6973416-a4ee-46bf-b539-b779c79079b6`
- employee: `7e5a3253-429a-4e8c-beab-980e291ee1c6`
- tenant: `00000000-0000-0000-0000-000000000001`

1. **bulk_assign_leads — admin call:** Insert test leads, call RPC as admin JWT, verify:
   - Each lead's `assigned_to_user_id` updated
   - `lead_timeline` has `assigned` events
   - Return shape `{assigned: N, per_employee: {…}}`

2. **bulk_assign_leads — employee forbidden:** Call as employee JWT → expect `permission_denied`.

3. **get_employee_active_lead_counts:** Verify returns correct active count per user.

4. **Warning threshold:** Assign 81 leads to an employee → warning banner must appear.

---

## Task Breakdown

- [ ] T1: Write + verify migration 0040 (bulk_assign_leads + get_employee_active_lead_counts)
- [ ] T2: Write send-bulk-assignment-notification edge function
- [ ] T3: Install @dnd-kit/core + @dnd-kit/utilities; write LeadsTable component
- [ ] T4: Write BulkAssignDialog — Step 1 (configure) + Step 2a (distribute preview)
- [ ] T5: Write BulkAssignDialog — Step 2b (manual DnD)
- [ ] T6: Update leads/page.tsx to use LeadsTable
- [ ] T7: Live-verify RPC via execute_sql; deploy edge fn
- [ ] T8: Code review + apply patches
- [ ] T9: Commit + push to main; sync _bmad-output mirrors
