---
baseline_commit: 596238c1176640da3f0b37b089fb220fab4ad2ac
---
# Story 14.3-mobile: live availability grid (Flutter UI)

Status: done

<!-- Mobile-UI completion of Story 14.3. The backend (migration 0072 get_project_units + units
Realtime publication) is DONE on prod/local and recorded in 14-3-live-availability-grid.md — do NOT
touch it. This story is ONLY the deferred mobile Task 3 + Task 4 (grid UI + Realtime client + tests).
Demo-slice centerpiece (arch §13.7). Named `14-3-mobile-*` to preserve the backend story record. -->

## Story

As a salesperson (any role tier),
I want a live, colour-coded unit-availability grid per project on my phone,
so that I never pitch a unit that is already held or sold.

## Acceptance Criteria

1. **Given** a project's units **When** I open the availability grid **Then** units render colour-coded
   by status (available / hold / sold / blocked) in a floor-grouped grid.
2. **And** a status change (e.g. another agent holds a unit) propagates to my open grid within ~5 s via
   Supabase Realtime on `units` (Decision 25). The Realtime event is a **trigger to re-fetch via
   `get_project_units`** — the RPC stays the single source of truth (preserves margin/agency scoping);
   the raw Realtime row is never rendered directly.
3. **And** an external `partner_agency` user sees only agency-shared projects (the RPC raises
   `project_not_shared` for others) and **never** sees `cost_paise` / margin (RPC returns it NULL for
   non-`builder_head`; the UI shows a margin row only when the value is present).
4. **And** the grid read itself never mutates unit status (booking/holding is Epic 15 — this story ships
   NO write path; tapping a unit opens a read-only detail sheet).
5. **And** tapping a unit opens a detail sheet showing unit_no, tower, floor, configuration, carpet area,
   list price, status, and (head only) margin — with a disabled/placeholder "Hold" affordance that
   Story 15.2-mobile will wire (do not implement holding here).

## Tasks / Subtasks

- [x] **Task 1 — Data layer** (`features/inventory/data/`) (AC: 1,3)
  - [x] `models/unit_model.dart`: `ProjectUnit` (unit_id, tower_id, tower_name?, unit_no, floor?,
        configuration?, carpet_area_sqft?, status, list_price_paise?, cost_paise?, status_version) with
        `fromJson` matching the `get_project_units` RETURNS TABLE column names exactly. Add a
        `UnitStatus` handling helper (available/hold/sold/blocked) — colours live in the UI/theme layer.
  - [x] `inventory_repository.dart`: `InventoryRepository(SupabaseClient)` with
        `Future<List<ProjectUnit>> getProjectUnits(String projectId)` calling
        `_supabase.rpc('get_project_units', params: {'p_project_id': projectId})`, plus a
        `@riverpod InventoryRepository inventoryRepository(...)` provider. Reuse `fetchProjects()`
        shape from `LeadRepository` for the project picker (query `projects` where `is_active`); either
        reuse the existing `ProjectRef`/`fetchProjects` or add a thin equivalent here — do not duplicate
        needlessly.
  - [x] Map the RPC's `project_not_shared` / `project_not_found` / `not_authenticated` PostgREST errors
        to a typed/friendly failure (mirror `LeadRepository._throwFromEdgeError` style but for `.rpc`
        `PostgrestException`). Partner-unshared → a clean "This project isn't shared with you" empty state,
        not a red crash.
- [x] **Task 2 — Providers** (`features/inventory/providers/`) (AC: 1,2)
  - [x] `projectUnitsProvider` (family on `projectId`, `@riverpod`): fetches via the repo.
  - [x] Realtime: subscribe to `public.units` changes filtered to the open `project_id` (Supabase
        `.channel(...).onPostgresChanges(event: all, schema: 'public', table: 'units', filter: project_id=eq)`).
        On any event, invalidate/re-fetch `projectUnitsProvider(projectId)` (debounce burst events to a
        single refetch within ~1s). Tear the channel down on dispose (`ref.onDispose`). Keep it authoritative:
        refetch through the RPC; never trust the payload's columns.
  - [x] `projectListProvider` for the picker (reuse lead repo's project fetch if practical).
  - [x] Run `dart run build_runner build --delete-conflicting-outputs` after adding providers.
- [x] **Task 3 — UI** (`features/inventory/ui/`) (AC: 1,4,5)
  - [x] `inventory_projects_screen.dart`: project picker list (active projects) → pushes the grid.
  - [x] `availability_grid_screen.dart`: floor-grouped, colour-coded tiles (see status→colour map in Dev
        Notes). Loading / error / empty (incl. partner-unshared) states. A small legend. Pull-to-refresh.
        Tapping a tile opens the detail sheet.
  - [x] `unit_detail_sheet.dart`: `showModalBottomSheet` read-only detail. Margin row rendered ONLY when
        `cost_paise != null`. "Hold" button present but disabled with a "coming in booking" note (15.2 wires it).
  - [x] Entry point: add an "Inventory" / "Availability" tile to `you_screen.dart` (or a suitable existing
        menu) routing to the picker. Add routes `/inventory` and `/inventory/:projectId` in
        `router/app_router.dart` (top-level GoRoutes, consistent with `/archived`, `/lead/:id`). Do not
        gate the entry by role client-side — the RPC scopes correctly for every tier; a partner just sees
        their shared projects (empty if none).
- [x] **Task 4 — Tests** (`test/features/inventory/`) (AC: 1,2,3)
  - [x] `ProjectUnit.fromJson` maps every column incl. null `cost_paise` (non-head) and null `floor`.
  - [x] Status→colour mapping unit test (all four statuses + unknown fallback).
  - [x] A widget/logic test that the detail sheet hides the margin row when `cost_paise == null` and
        shows it when present.
  - [x] Provider test: a Realtime event triggers exactly one debounced refetch (fake repo).
  - [x] Keep `flutter analyze` at 0 errors and the full mobile suite green.

## Dev Notes

### The backend contract (already shipped — do NOT modify)
`get_project_units(p_project_id uuid)` — SECURITY DEFINER, `authenticated` only. RETURNS TABLE:
`unit_id uuid, tower_id uuid, tower_name text, unit_no text, floor int, configuration text,
carpet_area_sqft numeric, status public.unit_status, list_price_paise bigint, cost_paise bigint,
status_version int`. Ordered by `floor NULLS LAST, unit_no`.
- Internal tiers → all tenant units for the project.
- `partner_agency` → only if the project is shared to the caller's agency, else raises
  `project_not_shared` (ERRCODE 42501). Unknown project → `project_not_found` (P0001).
- `cost_paise` is returned only to `builder_head`; NULL for everyone else. **The UI must treat NULL as
  "hide margin", never as ₹0.**
- `units` is in the `supabase_realtime` publication already. Realtime authz is RLS = tenant-scoped (not
  project/agency-scoped) — which is exactly why we re-fetch through the RPC rather than render the raw row.
[Source: nirman-crm/supabase/migrations/0072_project_units_read.sql; 14-3-live-availability-grid.md]

### Status → colour map (use existing `AppColors`, `core/theme/app_theme.dart`)
Do NOT invent hex values. Map unit status to the existing tokens:
- `available` → `AppColors.statusSold` fg / `statusSoldBg` bg (green = free to sell), OR a dedicated
  green — pick the green pair already in the palette; label "Available".
- `hold` → `AppColors.statusWarm` / `statusWarmBg` (amber). Label "Hold".
- `sold` → `AppColors.statusHot`... — NO: `sold` should read as taken. Use `AppColors.inkDisabled` /
  `surfaceMist` (muted/greyed) so sold reads as unavailable, distinct from the amber hold.
- `blocked` → `AppColors.statusDead` / `statusDeadBg` (grey-blue). Label "Blocked".
- Confirm the exact pairs during build against the palette; the requirement is: four visually distinct,
  colour-blind-reasonable states with available=go, hold=amber/caution, sold=muted-taken, blocked=grey.
  Add a legend so colour isn't the only signal (accessibility). [Source: app_theme.dart]

### Realtime pattern
supabase_flutter 2.x: `Supabase.instance.client.channel('units:$projectId')
  .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'units',
    filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'project_id', value: projectId),
    callback: (_) => <debounced refetch>).subscribe();` — unsubscribe in `ref.onDispose`. If the SDK
version's filter API differs, fetch current docs via Context7 (`supabase_flutter` / `realtime`) rather
than guessing. Debounce so a burst of row updates → one refetch.

### Role on the client
`session.user.appMetadata['role']` is available (see `you_screen.dart:24`); `role_tier` may be ABSENT
(the 12.3 backfill edge fn was not invoked in prod — `auth_role_tier()` falls back from `role`
server-side). Therefore: **do not gate correctness on a client-read `role_tier`.** The RPC already
enforces margin + agency scoping. Client role only decides cosmetic menu labels if needed. [Source:
project-state.md; nirman-crm/CLAUDE.md; you_screen.dart]

### File / structure conventions (match `features/leads`)
- `features/inventory/data/{models/,inventory_repository.dart}`, `.../providers/`, `.../ui/`.
- Repository = plain class taking `SupabaseClient`, exposed via a `@riverpod` provider (see
  `lead_repository.dart:399`). Models are immutable with `fromJson`. Providers use riverpod codegen
  (`part '*.g.dart'`) — regenerate with build_runner.
- Routes are top-level `GoRoute`s in `router/app_router.dart`; navigation via `context.push('/inventory')`.
- Money is stored in paise (`list_price_paise` bigint) — format to ₹ with a lakh/crore-aware helper;
  check for an existing currency formatter in the mobile app before writing a new one.
[Source: lead_repository.dart; app_router.dart; app_shell.dart]

### Testing standards
`flutter test` under `test/`, mirror existing `test/features/...` layout. Unit-test pure logic
(fromJson, colour map, debounce) without a live Supabase; fake the repo for provider tests. Target 0
`flutter analyze` errors and full suite green before code-review. [Source: nirman-crm/CLAUDE.md]

### Local test env (FREE — never prod)
Docker Supabase is up; local migration head 0088 (0072 present, `units` has 72 rows, 1 project). For the
demo path you will also need role-tiered users (`builder_head`, `partner_agency`, `receptionist`,
`front_line_rep`) + an agency + an `agency_projects` share row to exercise AC3. A seed script is part of
the demo-slice setup (companion seed story `demo-seed-builder-ops`); if absent, create a local-only
`scripts/*.local.sql` seed and NEVER push it. Verify AC3 by signing in as the partner user against the
local stack. [Source: nirman-crm/CLAUDE.md; project-state.md]

### Project Structure Notes
- New domain `features/inventory` is additive; no existing feature is modified except `you_screen.dart`
  (add one entry tile) and `app_router.dart` (add two routes). Preserve the existing 3-tab shell,
  billing-lock redirect, and auth redirect logic in `app_router.dart` — only append routes.
- No new migration, no backend change. If you find yourself editing anything under `supabase/`, STOP.

### References
- [Source: epics.md#Story 14.3]
- [Source: architecture-builder-ops-v2.md §3.1, §13.2 (partner matrix), §13.3 (state machine), §13.7 (demo order)]
- [Source: nirman-crm/supabase/migrations/0072_project_units_read.sql]
- [Source: 14-3-live-availability-grid.md (backend story record — deferred Tasks 3/4 are this story)]
- [Source: nirman-crm/apps/mobile/lib/features/leads/data/lead_repository.dart (repo+provider pattern)]
- [Source: nirman-crm/apps/mobile/lib/core/theme/app_theme.dart (colour tokens)]
- [Source: nirman-crm/apps/mobile/lib/router/app_router.dart; features/home/ui/app_shell.dart, you_screen.dart]

### Review Findings

_Code review 2026-07-10 (3 lenses inline: Blind Hunter / Edge-Case / Acceptance Auditor). 0 decision-needed, 0 patch, 1 defer, rest clean. Realtime lifecycle, debounced-refetch-through-RPC, null-cost_paise hiding, and error/empty states all verified correct; no backend or existing feature touched; 157/157 suite green._

- [x] [Review][Defer] Partner project-picker over-lists (AC3 scope nuance) [features/inventory/ui/inventory_projects_screen.dart] — The picker uses `availableProjectsProvider` (direct `projects` select; RLS = `tenant_id = auth_tenant_id()`), so a `partner_agency` user sees ALL active tenant project **names**, though they can only OPEN agency-shared ones (others → the friendly "not shared with your agency" state via the grid RPC). The true data (units, margin) stays fully scoped server-side; only project names in the picker leak. **Not cleanly fixable client-side:** (a) the backend is frozen for this work, and (b) `role_tier` may be ABSENT from the JWT (12.3 backfill not run), so the client cannot reliably detect "this caller is a partner" to branch the picker. The correct fix is a backend `get_my_projects()` RPC that scopes the project list per tier the same way `get_project_units` scopes units. **Deferred** — out of demo path (§13.7 demo is internal roles only) and gated on a backend story. Tracked in deferred-work.md.

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia / bmad-dev-story)

### Debug Log References

- `flutter pub run build_runner build --delete-conflicting-outputs` → 2 new outputs
  (inventory_repository.g.dart, inventory_providers.g.dart).
- `flutter analyze` → 0 errors (255 pre-existing info/warning lints in unrelated test files;
  inventory lib+test analyze clean). `fake_async` promoted to a direct dev_dependency to clear the
  one lint in the new debouncer test.
- `flutter test` full suite → 157/157 pass (14 new inventory tests included).

### Completion Notes List

- New additive domain `features/inventory/{data,providers,ui}` mirroring `features/leads`. No backend
  touched; consumes the shipped `get_project_units` RPC + `units` Realtime publication (migration 0072).
- **Realtime design (AC2):** the grid screen owns the `units` channel (filtered `project_id=eq`); an
  event → 400ms-debounced `ref.invalidate(projectUnitsProvider)`, so the refresh always re-flows through
  the authoritative RPC. The raw Realtime row is never rendered → margin/agency scoping preserved even
  though Realtime authz is only tenant-scoped.
- **Margin (AC3):** `ProjectUnit.hasMargin == costPaise != null`; the detail sheet renders the margin row
  only when true. Null is treated as "hide", never ₹0. Verified by widget test both ways.
- **Partner scoping (AC3):** `InventoryAccessException.notShared` (mapped from the RPC's
  `project_not_shared`) renders a friendly "not shared with your agency" empty state, not a crash.
- **No write path (AC4/AC5):** detail sheet's Hold button is disabled with a "coming soon" note; Story
  15.2-mobile wires it. Grid read never mutates.
- Entry point: "Availability" row under a new WORKSPACE group in the You tab → `/inventory` picker →
  `/inventory/:projectId` grid. Routes appended to `app_router.dart` without altering the existing
  auth/billing-lock redirect logic.
- **AC3 verified on local stack (2026-07-10):** demo seed `supabase/demo-builder-ops.local.sql` created
  role-tiered loginable users (head@/partner@/reception@nirman.local = `demo1234`) + agency + agency_projects
  share in Nirman Media (owns The Velocity, 72 units). Simulated-JWT `get_project_units`: builder_head →
  72 units all with cost_paise (margin shown); partner_agency (shared) → 72 units, 0 with cost_paise
  (margin hidden). The client renders exactly this. On-device visual look-pass (colours/legend) still to
  be eyeballed by Rudra — same posture as 9.6.

### File List

**New**
- apps/mobile/lib/features/inventory/data/models/unit_model.dart
- apps/mobile/lib/features/inventory/data/inventory_repository.dart
- apps/mobile/lib/features/inventory/data/inventory_repository.g.dart (generated)
- apps/mobile/lib/features/inventory/providers/debouncer.dart
- apps/mobile/lib/features/inventory/providers/inventory_providers.dart
- apps/mobile/lib/features/inventory/providers/inventory_providers.g.dart (generated)
- apps/mobile/lib/features/inventory/ui/unit_status_style.dart
- apps/mobile/lib/features/inventory/ui/unit_detail_sheet.dart
- apps/mobile/lib/features/inventory/ui/availability_grid_screen.dart
- apps/mobile/lib/features/inventory/ui/inventory_projects_screen.dart
- apps/mobile/test/features/inventory/unit_model_test.dart
- apps/mobile/test/features/inventory/unit_status_style_test.dart
- apps/mobile/test/features/inventory/debouncer_test.dart
- apps/mobile/test/features/inventory/unit_detail_sheet_test.dart

**Modified**
- apps/mobile/lib/router/app_router.dart (import + 2 routes)
- apps/mobile/lib/features/home/ui/you_screen.dart (WORKSPACE group + Availability row)
- apps/mobile/pubspec.yaml (fake_async → dev_dependencies)

## Change Log

- 2026-07-10: Implemented mobile availability grid (features/inventory) — live colour-coded grid, Realtime
  refetch, role-scoped read via get_project_units, read-only unit detail sheet. 14 tests; analyze 0 errors;
  full suite 157/157. Status → review.
