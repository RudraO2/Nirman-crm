---
baseline_commit: 596238c1176640da3f0b37b089fb220fab4ad2ac
---
# Story 15.2-mobile: hold a unit for a lead (Flutter UI)

Status: done

<!-- Mobile-UI completion of Story 15.2. Backend hold_unit() CAS RPC is DONE on prod/local
(migration 0076) — do NOT touch it. This story is the deferred mobile Task 4: the Hold action on the
14.3 unit detail sheet + lead picker + amber-tile transition + countdown. Builds directly on the
14.3-mobile grid/detail sheet (features/inventory). Demo-slice step 3. -->

## Story

As a salesperson,
I want to place a hold on an available unit for one of my leads and see the hold countdown,
so that I lock the unit while the customer decides — without race conditions.

## Acceptance Criteria

1. **Given** the 14.3 unit detail sheet for an `available` unit **When** I tap "Hold" **Then** I pick one
   of my own active leads and the app calls `hold_unit(p_unit_id, p_lead_id)`.
2. **And** on success the unit tile flips to amber (`hold`) within ~5s via the existing Realtime refetch
   (no new realtime wiring — 14.3's `units` channel already drives it), and I see the hold's countdown to
   `expires_at` (project `hold_timer_hours`, 24h on the demo project).
3. **And** if the unit was taken concurrently the RPC returns `unit_unavailable` and I get a clean
   "Just taken by someone else" message (not a red crash), and the grid shows it as held.
4. **And** a `receptionist` cannot hold (RPC `permission_denied`) — the Hold action surfaces a clear
   "not allowed for your role" message rather than a raw error. (Ownership: rep/partner may hold only
   their OWN lead's unit; the RPC enforces `not_your_lead`.)
5. **And** the hold action never fabricates client state — the amber flip and countdown come from the
   RPC result / the authoritative refetch, never an optimistic guess that could diverge from the server.

## Tasks / Subtasks

- [x] **Task 1 — Repo: hold_unit** (`features/inventory/data/inventory_repository.dart`) (AC: 1,3,4)
  - [x] `Future<UnitHold> holdUnit(String unitId, String leadId)` → `_supabase.rpc('hold_unit',
        params: {'p_unit_id': unitId, 'p_lead_id': leadId})`; parse the returned jsonb
        `{hold_id, unit_id, status_version, expires_at}` into a `UnitHold` model.
  - [x] Extend the typed-error mapping: map `unit_unavailable` → a `HoldConflict` flag, `not_your_lead`
        / `permission_denied` / `receptionist` → a `HoldNotAllowed` flag, others → generic. Reuse the
        `PostgrestException.message.contains(...)` approach already in `InventoryAccessException` (either
        extend it or add a sibling `HoldException`). Keep messages user-facing and calm.
  - [x] `UnitHold` model in `data/models/` (holdId, unitId, statusVersion, expiresAt as DateTime).
- [x] **Task 2 — Lead picker + hold flow** (`features/inventory/ui/`) (AC: 1,2,4)
  - [x] Enable the previously-disabled "Hold" button on `unit_detail_sheet.dart` **only** when
        `unit.status == available`. Tapping it opens a lead picker.
  - [x] Lead picker: reuse `myLeadsProvider` (the caller's own active leads) — a simple searchable list
        sheet. Selecting a lead calls the repo. Show a spinner/disable during the call.
  - [x] On success: close the sheets, invalidate `projectUnitsProvider(projectId)` (belt-and-suspenders
        with Realtime), and show a confirmation with the live countdown (see Task 3). On `HoldConflict`
        → calm snackbar "Just taken — refreshing"; on `HoldNotAllowed` → "You can't hold this unit".
  - [x] `receptionist` note: the RPC is the gate. Optionally hide the Hold button if we can *cheaply*
        tell the caller is a receptionist from `role_tier` in the JWT — but since `role_tier` may be
        absent, DO NOT rely on it for correctness; the RPC denial + friendly message is the contract.
- [x] **Task 3 — Countdown widget** (`features/inventory/ui/hold_countdown.dart`) (AC: 2)
  - [x] A reusable ticking `HoldCountdown(expiresAt)` widget: shows "Held · 23h 58m left", turns
        amber→red as it nears zero, shows "Expired" past `expiresAt`. Ticks via a 1s `Timer` (or
        `Stream.periodic`); cancels on dispose. Extract the pure "duration → label" formatter so it is
        unit-testable without a running clock. (Reused by Story 15.5 booking dashboard.)
  - [x] Show the countdown for a `hold` unit on its detail sheet. To read an existing hold's
        `expires_at`, add a small repo read of `unit_holds` for the unit (active hold: `released_at IS
        NULL`) IF `unit_holds` RLS permits a tenant read (verify during dev on the local stack). If RLS
        does not allow it, scope the countdown to the just-placed hold (from the RPC result) and note the
        limitation — do NOT invent a new RPC (backend frozen).
- [x] **Task 4 — Tests** (`test/features/inventory/`) (AC: all)
  - [x] `UnitHold.fromJson` parses the RPC jsonb incl. `expires_at`.
  - [x] Countdown label formatter: hours/min/"Expired" boundaries.
  - [x] Error mapping: `unit_unavailable`→conflict, `permission_denied`/`not_your_lead`→not-allowed.
  - [x] Widget test: Hold button enabled only for `available`; disabled for hold/sold/blocked.
  - [x] `flutter analyze` 0 errors; full suite green.

## Dev Notes

### The backend contract (already shipped — do NOT modify)
`hold_unit(p_unit_id uuid, p_lead_id uuid)` → jsonb `{hold_id, unit_id, status_version, expires_at}`.
Two stacked guards (CAS `available→hold` + `unit_holds_one_active_idx`); the race loser gets
`unit_unavailable` (ERRCODE 42501), never a 500. Errors: `not_authenticated`, `permission_denied`
(receptionist), `lead_not_found`, `not_your_lead`, `hold_requires_verified_visit` (only if the tenant
flag is ON — default OFF), `unit_not_found`, `hold_timer_not_configured`, `unit_unavailable`.
`expires_at = now() + project.hold_timer_hours`. Ownership: front_line_rep/partner → own leads only;
team_leader → visible subtree; builder_head → any tenant lead; receptionist → denied.
[Source: nirman-crm/supabase/migrations/0076_hold_unit.sql; 15-2-hold-unit-compare-and-swap.md]

### Builds on 14.3-mobile (already done)
Grid + detail sheet + Realtime `units` channel + `projectUnitsProvider` already exist in
`features/inventory`. This story only ADDS the write path (hold) + countdown; the amber flip rides the
existing Realtime→debounced-refetch. Keep the "refetch through the RPC, never render raw realtime rows"
discipline. [Source: 14-3-mobile-availability-grid.md]

### Lead picker
Reuse `myLeadsProvider` (`features/leads/providers/lead_providers.dart`) for the caller's own active
leads — no new query. Filter to active/holdable leads as needed. A partner holds only their own lead's
unit; the RPC enforces it, the picker just lists the caller's leads.

### No optimistic lying (AC5)
Do not locally set the tile to amber before the RPC confirms. Drive the flip from the RPC success +
`invalidate(projectUnitsProvider)` and the Realtime refetch. On conflict, refetch shows the true state.

### Local verification (FREE — never prod)
Seed already applied: `supabase/demo-builder-ops.local.sql` (head@/partner@/reception@nirman.local =
`demo1234`; The Velocity 72 units, 24h timer; rep1@nirman has own leads). Verify on the local stack:
rep holds own-lead unit → success + amber + countdown; second concurrent hold → `unit_unavailable`;
receptionist → `permission_denied`. Simulated-JWT SQL is acceptable for the guard checks (as used to
verify 14.3 AC3); the widget/formatter logic is unit-tested. [Source: nirman-crm/CLAUDE.md]

### Project Structure Notes
Additive within `features/inventory`. Only `unit_detail_sheet.dart` changes materially (enable + wire
Hold); everything else is new files. No backend, no migration.

### References
- [Source: epics.md#Story 15.2; architecture-builder-ops-v2.md §4.2, §13.2, §13.6]
- [Source: nirman-crm/supabase/migrations/0076_hold_unit.sql]
- [Source: 15-2-hold-unit-compare-and-swap.md (backend record — deferred Task 4 is this story)]
- [Source: 14-3-mobile-availability-grid.md (grid/detail/realtime this builds on)]

### Review Findings

_Code review 2026-07-10 (3 lenses inline). 0 decision-needed, 0 patch, 1 defer, rest clean. Verified: BuildContext-safe async (ScaffoldMessenger + Navigator captured before the first await), AC5 (amber flip only from the authoritative refetch, never optimistic), `unit_holds` tenant-scoped read for the countdown, HoldException mapping (conflict/notAllowed/generic), Timer cleanup on dispose. Guards verified live on the local stack. 168/168 suite, analyze 0. No backend touched._

- [x] [Review][Defer] Hold lead-picker shows only the caller's OWN leads [features/inventory/ui/hold_lead_picker_sheet.dart] — The picker reuses `myLeadsProvider` (caller's own active leads). The `hold_unit` RPC additionally lets `builder_head` hold for ANY tenant lead and `team_leader` for their visible subtree, so via the UI a head/leader can only hold for a lead they personally own — narrower than the RPC. **Acceptable + deferred:** holding is overwhelmingly a front-line-rep action; a head/leader who needs to hold can do so for their own lead. Widening it needs a team-lead-scoped lead read (a get_team_leads/visible_user_ids surface — Story 12.5-mobile territory), not this story. Logged in deferred-work.md.

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia / bmad-dev-story)

### Debug Log References

- build_runner → activeHold provider generated. `flutter analyze` 0 errors. `flutter test` full suite
  **168/168** (11 new inventory tests, 25 total in features/inventory).
- Live guard verification on local Docker via simulated-JWT `hold_unit`: builder_head hold →
  `{hold_id, expires_at (24h)}`; receptionist → `permission_denied: receptionist cannot hold units`;
  re-hold same unit → `unit_unavailable`. All rolled back (no state left; unit still available).

### Completion Notes List

- Added the write path to `features/inventory` on top of the 14.3 grid. New: `UnitHold` model,
  `hold_countdown.dart` (ticking widget + pure `formatRemaining`), `hold_lead_picker_sheet.dart`.
  Repo gained `holdUnit` + `getActiveHold` + typed `HoldException` (conflict / notAllowed / generic).
- **AC5 (no optimistic lying):** the tile flips amber only from the authoritative refetch
  (`invalidate(projectUnitsProvider)` + the existing Realtime channel) after the RPC confirms — never a
  local guess. On `unit_unavailable` we invalidate + show "Just taken — refreshing", so the grid snaps
  to the true state.
- **AC4 (receptionist):** the RPC is the gate; `permission_denied`/`not_your_lead` → calm "You can't
  hold this unit". No client tier-gating (role_tier may be absent from JWT).
- **Countdown:** `unit_holds` SELECT RLS is tenant-scoped, so a held unit's detail sheet reads its active
  hold (`released_at IS NULL`) directly for the live countdown — no new RPC needed.
- `unit_detail_sheet.dart` became a `ConsumerStatefulWidget` (in-flight state + hold call). Grid tile
  now passes `projectId` through so the sheet can invalidate the right provider.

### File List

**New**
- apps/mobile/lib/features/inventory/data/models/unit_hold_model.dart
- apps/mobile/lib/features/inventory/ui/hold_countdown.dart
- apps/mobile/lib/features/inventory/ui/hold_lead_picker_sheet.dart
- apps/mobile/test/features/inventory/hold_test.dart

**Modified**
- apps/mobile/lib/features/inventory/data/inventory_repository.dart (holdUnit, getActiveHold, HoldException)
- apps/mobile/lib/features/inventory/providers/inventory_providers.dart (activeHoldProvider)
- apps/mobile/lib/features/inventory/providers/inventory_providers.g.dart (generated)
- apps/mobile/lib/features/inventory/ui/unit_detail_sheet.dart (Consumer + hold flow + countdown)
- apps/mobile/lib/features/inventory/ui/availability_grid_screen.dart (thread projectId)
- apps/mobile/test/features/inventory/unit_detail_sheet_test.dart (projectId + Hold-gating tests)
- nirman-crm/supabase/demo-builder-ops.local.sql (demo seed — local only, not committed)

## Change Log

- 2026-07-10: Implemented mobile hold-a-unit (Story 15.2) — Hold action on the 14.3 detail sheet + own-lead
  picker + CAS `hold_unit` + amber flip via authoritative refetch + live countdown (read from unit_holds).
  Typed HoldException (conflict/notAllowed). 11 new tests (168/168 suite), analyze 0. Guards verified live
  on local stack (head success, receptionist denied, conflict). Status → review.
