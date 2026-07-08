# Story 14.3: live availability grid (anti double-book reads)

Status: review  (migration 0072 written + applied + scoping smoke ALL PASS 2026-06-28; Realtime client + tiles UI deferred)

## Implementation (2026-06-28)

**File:** `nirman-crm/supabase/migrations/0072_project_units_read.sql`

- **New `agency_projects` table** (tenant_id, agency_id, project_id, unique) — the explicit project→agency share the §13.2 matrix requires but arch §3.1 didn't enumerate (logged in arch correction §15.2). RLS ENABLE+FORCE; SELECT=tenant, DML=admin-only (mirrors agencies/0057).
- **`get_project_units(p_project_id)`** SECURITY DEFINER read: internal tiers → all tenant units for the project; `partner_agency` → only if shared to caller's agency (else `project_not_shared`); `cost_paise` returned **only** to `builder_head` (NULL otherwise). Read-only (no mutation). Returns tower join + status_version (for 15.2 CAS).
- **Realtime:** `units` added to `supabase_realtime` publication (guarded) → ≤5s status propagation. Caveat noted in header: Realtime authz is RLS (tenant-scoped, not project-scoped); partners are tenant-bounded — authoritative scoping is the RPC; clients subscribe only to projects opened via it.

**Tested (local runtime):** head cost_paise=4000000000; rep units=6 & cost_paise NULL; partner-unshared denied (project_not_shared); partner-shared sees 6 units, cost_paise NULL; units in supabase_realtime publication.

**Deferred:** mobile + admin colour-coded grid tiles + Realtime subscription client (Tasks 2-3); a head RPC/UI to manage agency_projects shares (table + admin DML exist now).

## Story

As a salesperson,
I want a real-time availability grid per project,
so that I never pitch a unit that's already held or sold.

## Acceptance Criteria

1. **Given** a project's units **When** I open the availability grid **Then** units render colour-coded by status (available/hold/sold/blocked).
2. **And** status changes propagate to viewers within 5 seconds via Supabase Realtime (Decision 25).
3. **And** an external `partner_agency` user sees only agency-shared projects, with `cost_paise`/margin omitted.
4. **And** the grid read never itself mutates status (booking is Epic 15).

## Tasks / Subtasks

- [ ] **Task 1 — Read RPC / view**: `get_project_units(p_project_id)` returning unit_no, floor, configuration, carpet_area_sqft, status, list_price_paise — **never `cost_paise`** for non-head. Tenant + (for partners) agency-shared-project scoped.
- [ ] **Task 2 — Realtime**: subscribe to `units` changes for the open project (Supabase Realtime channel, RLS-aware). Update tiles on status change.
- [ ] **Task 3 — Mobile + admin grid UI**: colour-coded tiles by status; tap → unit detail (hold action lives in 15.2).
- [ ] **Task 4 — Tests**: partner sees only shared projects + no margin; status change reflects ≤5s; read does not mutate.

## Dev Notes

- Reuse Supabase Realtime (Decision 25, already used for dashboard counters). [Source: architecture.md Decision 25]
- Margin privacy: `cost_paise` excluded from this read path entirely. [Source: architecture-builder-ops-v2.md §2.2 note, §3.1, §13.2]
- This is the **demo centerpiece** (John, arch §13.7) — build it real, build it polished.

## References
- [Source: epics.md#Story 14.3; architecture-builder-ops-v2.md §3.1, §13.2, §13.7]
