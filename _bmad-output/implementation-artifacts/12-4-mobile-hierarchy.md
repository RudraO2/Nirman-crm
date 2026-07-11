---
baseline_commit: 596238c1176640da3f0b37b089fb220fab4ad2ac
---
# Story 12.4-mobile: builder-head manages the reporting hierarchy (Flutter UI)

Status: done

<!-- Mobile-UI completion of Story 12.4. The backend (migration 0059 set_user_hierarchy +
role_tier_rank + the manage-employee deactivation-with-reports block) is DONE on prod and recorded in
12-4-builder-head-manages-hierarchy.md — do NOT touch it. This story is ONLY the deferred mobile UI:
the hierarchy-management screen surfaced to builder-head. Parity reference = the admin web /hierarchy
page (apps/admin/src/app/(app)/hierarchy). Named `12-4-mobile-*` to preserve the backend story record.
Slice 2 of the mobile builder-ops build (Slice 1 = features/inventory, done). -->

## Story

As a Builder Head,
I want to set each team member's tier and reporting line from my phone,
so that the org tree reflects real reporting lines without opening the web admin.

## Acceptance Criteria

1. **Given** I am a builder-head (JWT `role='admin'`) **When** I open the Organization screen **Then** it
   lists the tenant's active users with each user's tier (as a coloured pill), their "reports to" manager
   name, and their agency (for external/partner users only).
2. **And** editing a user lets me set `role_tier`, `reports_to` (only for ladder tiers), and `agency`
   (only for `partner_agency`) and calls `set_user_hierarchy(p_user_id, p_role_tier, p_reports_to,
   p_agency_id)` — the RPC is authoritative; the client never mutates `users` directly for hierarchy.
3. **And** the "reports to" picker offers only strictly-higher **ladder** tiers in the same tenant
   (rep→leader/head, leader→head), never the user themselves; off-ladder tiers (`partner_agency`,
   `receptionist`) hide the reports-to field entirely (RPC forbids a reports_to for them).
4. **And** selecting `partner_agency` requires an agency; saving without one is blocked client-side with a
   calm message, matching the RPC's `agency_required_for_partner` guard.
5. **And** RPC rejections map to calm, human messages (no red PostgREST dump): a reporting cycle
   (`reporting_cycle_detected`), a too-low manager (`reports_to_must_be_higher_tier`), an off-ladder
   reports_to (`off_ladder_tier_has_no_reports_to`), a missing/foreign agency
   (`agency_required_for_partner` / `agency_not_found`), and a generic fallback.
6. **And** I can see the tenant's partner agencies and create a new one inline (insert into `agencies`),
   so a partner user can then be pointed at it.
7. **And** the Organization entry point is shown only to a builder-head; a non-admin user never sees it
   (best-effort client gate on `role='admin'` — the RPC re-checks server-side regardless, so a leaked
   entry is still safe: every mutation is denied `permission_denied`).

## Tasks / Subtasks

- [ ] **Task 1 — Data layer** (`features/hierarchy/data/`) (AC: 1,2,6)
  - [ ] `models/hierarchy_user.dart`: immutable `HierarchyUser` (id, email_or_username, role, role_tier?,
        reports_to_user_id?, agency_id?, is_external, is_active) with `fromJson` matching the `users`
        select column names. Add a pure `RoleTier` enum + helpers: `fromDb(String?)`, `label`, `rank`
        (super=4, head=3, leader=2, rep=1, partner/reception=0), `isLadder` (super/head/leader/rep). Keep
        it Flutter-free (no theme import) so it stays unit-testable — pill colours live in the UI layer.
  - [ ] `models/agency.dart`: immutable `Agency` (id, name) + `fromJson`.
  - [ ] `hierarchy_repository.dart`: `HierarchyRepository(SupabaseClient)` with:
        - `Future<List<HierarchyUser>> fetchUsers()` — `.from('users').select('id, email_or_username,
          role, role_tier, reports_to_user_id, agency_id, is_external, is_active').eq('is_active',
          true).order('email_or_username')` (mirrors admin `page.tsx`; RLS scopes to tenant + admin read).
        - `Future<List<Agency>> fetchAgencies()` — `.from('agencies').select('id, name').order('name')`.
        - `Future<void> setHierarchy({required String userId, required RoleTier tier, String? reportsTo,
          String? agencyId})` — `.rpc('set_user_hierarchy', params: {p_user_id, p_role_tier: tier.dbValue,
          p_reports_to, p_agency_id})`.
        - `Future<void> createAgency(String name)` — `.from('agencies').insert({'name': name.trim()})`
          (tenant_id is defaulted server-side / set by RLS default — confirm on local; the admin insert
          passes tenant_id explicitly, so pass `auth_tenant_id` from the session's `app_metadata` if the
          column has no default). **Verify which on the local stack before finalizing.**
        - Expose a `@riverpod HierarchyRepository hierarchyRepository(...)` provider.
  - [ ] Map RPC `PostgrestException.message` tokens to a typed `HierarchyException` with a `friendly`
        getter (mirror `InventoryAccessException.fromPostgrest` style): `reporting_cycle_detected`,
        `reports_to_must_be_higher_tier`, `off_ladder_tier_has_no_reports_to`,
        `agency_required_for_partner`, `agency_not_found`, `permission_denied`, else the raw message.
- [ ] **Task 2 — Providers** (`features/hierarchy/providers/`) (AC: 1,6)
  - [ ] `hierarchyUsersProvider` (`@riverpod Future<List<HierarchyUser>>`) → repo `fetchUsers()`.
  - [ ] `agenciesProvider` (`@riverpod Future<List<Agency>>`) → repo `fetchAgencies()`.
  - [ ] After a successful `set_user_hierarchy` / `createAgency`, `ref.invalidate` the affected provider so
        the list re-fetches through the source of truth (same authoritative-refetch posture as Slice 1).
  - [ ] Run `dart run build_runner build --delete-conflicting-outputs` after adding providers.
- [ ] **Task 3 — UI** (`features/hierarchy/ui/`) (AC: 1,2,3,4,5,6)
  - [ ] `organization_screen.dart`: AppBar "Organization"; loading / error / empty states. A "Partner
        agencies" card (list of pills + a "New agency" inline add row). Then the user list: each row shows
        name (+ "(you)" for the current uid), a `TierPill`, reports-to manager name, and agency name (only
        when `is_external`). Tapping a row opens the edit sheet. Pull-to-refresh invalidates both providers.
  - [ ] `tier_pill.dart`: maps `RoleTier` → an `AppColors` pair (see Dev Notes). Never raw hex.
  - [ ] `edit_hierarchy_sheet.dart` (`showModalBottomSheet`): a Tier dropdown (all six tiers); a Reports-to
        dropdown shown ONLY for ladder tiers, options = users filtered to strictly-higher ladder rank and
        `id != editing.id`, plus a "— None (top of tree) —" option; an Agency dropdown shown ONLY for
        `partner_agency`, options = agencies (disabled hint when none exist). Save button: client-validates
        partner-needs-agency, calls the repo, on `HierarchyException` shows the `friendly` message inline
        (no crash), on success closes + invalidates + shows a confirmation snackbar.
  - [ ] Entry point: add an "Organization" row to the WORKSPACE group in `you_screen.dart`, routing to
        `/organization`, shown only when `session.user.appMetadata['role'] == 'admin'`. Add a top-level
        `GoRoute('/organization')` in `router/app_router.dart` (consistent with `/inventory`). Do not alter
        the auth/billing-lock redirect logic — only append.
- [ ] **Task 4 — Tests** (`test/features/hierarchy/`) (AC: 1,2,3,4,5)
  - [ ] `HierarchyUser.fromJson` maps every column incl. null `role_tier`, null `reports_to_user_id`, null
        `agency_id`.
  - [ ] `RoleTier` helpers: `fromDb` (incl. unknown → a safe fallback), `rank`, `isLadder`, `label`.
  - [ ] Manager-options filter logic (pure): given a tier + a user list, returns only strictly-higher
        ladder users, excluding self; empty when none qualify.
  - [ ] `HierarchyException.friendly` maps each known token to its message and falls back for unknown.
  - [ ] Widget/logic test: the edit sheet hides reports-to for `partner_agency`/`receptionist`, shows the
        agency field for `partner_agency`, and blocks save when partner has no agency.
  - [ ] Keep `flutter analyze` at 0 errors and the full mobile suite green.
- [ ] **Task 5 — Verify guards live on local Docker** (AC: 2,5,7)
  - [ ] With the demo seed applied, sign in as `head@nirman.local` / `demo1234`; confirm the user list
        loads and an edit round-trips (e.g. set a rep's reports_to to the head; flip a user to
        partner_agency + Skyline Partners).
  - [ ] Simulated-JWT SQL (pattern below) to prove the RPC rejects: rep→rep reports_to
        (`reports_to_must_be_higher_tier`), a cycle (`reporting_cycle_detected`), partner w/o agency
        (`agency_required_for_partner`), and a non-admin caller (`permission_denied`). The UI maps each to
        its calm message.

## Dev Notes

### The backend contract (already shipped — do NOT modify)
`set_user_hierarchy(p_user_id uuid, p_role_tier public.role_tier, p_reports_to uuid DEFAULT NULL,
p_agency_id uuid DEFAULT NULL) RETURNS jsonb` — SECURITY DEFINER, `authenticated` only, admin-guarded
(`app_metadata.role = 'admin'`, else raises `permission_denied` ERRCODE 42501). It:
- Requires the target user in the caller's tenant (`user_not_found` P0002 otherwise).
- `partner_agency` → requires `p_agency_id` in-tenant (`agency_required_for_partner` 22023 /
  `agency_not_found` P0002), sets `is_external=true`. Any other tier → `is_external=false`, agency cleared.
- Off-ladder tiers (`partner_agency`, `receptionist`) must have NULL reports_to
  (`off_ladder_tier_has_no_reports_to` 22023).
- Ladder tiers with a reports_to: manager must be **strictly higher** rank (`role_tier_rank`:
  super=4 > head=3 > leader=2 > rep=1; off-ladder=0) → else `reports_to_must_be_higher_tier` 22023;
  `cannot_report_to_self` 22023; upward-recursive cycle check → `reporting_cycle_detected` 22023.
- Audits to `user_events` (`hierarchy_changed`).
[Source: nirman-crm/supabase/migrations/0059_hierarchy_mgmt.sql; 12-4-builder-head-manages-hierarchy.md]

Deactivation-with-reports (AC-4 of the backend story) lives in the `manage-employee` edge fn, NOT this
mobile story — mobile does not deactivate users. Do not build a deactivation path here.

### The role_tier values (public.role_tier enum, migration 0057)
`super_admin, builder_head, team_leader, front_line_rep, partner_agency, receptionist`. The `dbValue`
strings must match exactly. Labels for the UI: Super Admin / Builder Head / Team Leader / Front-line Rep /
Partner · Agency / Reception.

### Tier pill → `AppColors` (core/theme/app_theme.dart — do NOT invent hex)
Mirror the admin palette intent using existing tokens:
- `super_admin` → bg `AppColors.evergreen`, fg `AppColors.brassBright`
- `builder_head` → bg `AppColors.brass`, fg `Colors.white`
- `team_leader` → bg `AppColors.brassSoft`, fg `Color(0xFF6E5423)` (already used literally in you_screen)
- `front_line_rep` → bg `AppColors.paper`, fg `AppColors.inkSecondary`, 1px `AppColors.line2` border
- `partner_agency` → bg `AppColors.statusColdBg`, fg `AppColors.statusCold`
- `receptionist` → bg `AppColors.mist`, fg `AppColors.inkDisabled`
Row/card styling: reuse the `_RowItem`/card idiom from `you_screen.dart` (paper fill, `AppColors.line`
border, 16 radius). [Source: app_theme.dart; you_screen.dart; hierarchy-client.tsx TIER_PILL map]

### Role on the client (why the entry gate is best-effort only)
`session.user.appMetadata['role']` IS present (`'admin'` for a builder-head; see `you_screen.dart:24`).
`role_tier` may be ABSENT from the JWT (the 12.3 backfill fn was not invoked in prod). Therefore:
- Gate the **menu entry** on `role == 'admin'` (builder-head ≡ admin) — cosmetic only.
- NEVER gate correctness on a client-read `role_tier`. `set_user_hierarchy` re-checks `role='admin'`
  server-side, so even a leaked screen can mutate nothing (every call → `permission_denied`).
[Source: project-state.md; nirman-crm/CLAUDE.md; you_screen.dart]

### Parity reference — admin /hierarchy (behaviour to match, not code to port)
`apps/admin/src/app/(app)/hierarchy/{page.tsx,hierarchy-client.tsx}`:
- `page.tsx` server-selects `users` (is_active=true, ordered) + `agencies` (id,name).
- `hierarchy-client.tsx`: TIER/RANK/LADDER maps; `managerOptions` = users filtered to
  `isLadder(u.role_tier) && RANK[u.role_tier] > RANK[tier] && u.id !== user.id`; partner-needs-agency
  client guard; edit dialog calls `set_user_hierarchy` with `p_reports_to = ladder && reportsTo!==NONE ?
  reportsTo : null` and `p_agency_id = isPartner ? agencyId : null`; AgencyManager inserts into `agencies`.
Match this logic exactly in Dart. [Source: hierarchy-client.tsx]

### File / structure conventions (match `features/inventory` from Slice 1)
- `features/hierarchy/{data/{models/},providers/,ui/}`. Repository = plain class taking `SupabaseClient`,
  exposed via a `@riverpod` provider (see `inventory_repository.dart`). Models immutable with `fromJson`.
  Providers use riverpod codegen (`part '*.g.dart'`) — regenerate with build_runner.
- Typed exception mapped from `PostgrestException` (see `InventoryAccessException.fromPostgrest`).
- Routes are top-level `GoRoute`s in `router/app_router.dart`; nav via `context.push('/organization')`.
[Source: features/inventory/*; app_router.dart; you_screen.dart]

### Testing standards
`flutter test` under `test/`, mirror `test/features/inventory/`. Unit-test pure logic (fromJson, RoleTier
helpers, manager-options filter, exception mapping) without a live Supabase; fake the repo for any
provider/widget test. Target 0 `flutter analyze` errors and full suite green before code-review.
[Source: nirman-crm/CLAUDE.md; 14-3-mobile story]

### Local test env (FREE — never prod)
Docker Supabase up; demo seed `supabase/demo-builder-ops.local.sql` (LOCAL ONLY, gitignored) seeds
role-tiered loginable users in tenant Nirman Media: `head@nirman.local` (builder_head, role=admin),
`partner@nirman.local` (partner_agency, agency Skyline Partners), `reception@nirman.local` (receptionist),
plus `rep1@nirman` (front_line_rep) and `admin@nirman.local` (super_admin). All `demo1234`. Apply:
`docker exec -i supabase_db_supabase psql -U postgres -d postgres < supabase/demo-builder-ops.local.sql`.
Verify guards via simulated-JWT SQL:
```sql
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub":"<head-uid>","app_metadata":{"role":"admin","tenant_id":"00000000-0000-0000-0000-000000000001"}}';
  select set_user_hierarchy('<rep-uid>', 'front_line_rep', '<another-rep-uid>');  -- expect reports_to_must_be_higher_tier
rollback;
```
[Source: project-state.md §Demo seed; nirman-crm/CLAUDE.md]

### Project Structure Notes
- New domain `features/hierarchy` is additive; the only existing files touched are `you_screen.dart` (one
  WORKSPACE row, admin-gated) and `app_router.dart` (one route). Preserve the 3-tab shell + auth/billing
  redirects — append only.
- No new migration, no backend change. If you find yourself editing anything under `supabase/`, STOP.

### References
- [Source: epics.md#Story 12.4]
- [Source: architecture-builder-ops-v2.md §2.1 constraints, §13.1]
- [Source: nirman-crm/supabase/migrations/0059_hierarchy_mgmt.sql]
- [Source: 12-4-builder-head-manages-hierarchy.md (backend story record — deferred web/mobile UI is this story)]
- [Source: nirman-crm/apps/admin/src/app/(app)/hierarchy/{page.tsx,hierarchy-client.tsx} (parity behaviour)]
- [Source: nirman-crm/apps/mobile/lib/features/inventory/* (Slice 1 repo+provider+exception+router pattern)]
- [Source: nirman-crm/apps/mobile/lib/core/theme/app_theme.dart; features/home/ui/you_screen.dart]

## Review Findings

_Code review 2026-07-11 (3 lenses inline: Blind Hunter / Edge-Case Hunter / Acceptance Auditor).
**0 confirmed findings, 0 patches, 1 investigated-and-refuted, 1 low observation.** ACs 1–7 all
satisfied; RPC-authoritative wiring, error mapping, manager-options filter, and the admin-gated entry
verified. Full suite 193/193, analyze 0 errors._

- [x] [Review][Refuted] **Suspected DropdownButtonFormField stale-value crash** [edit_hierarchy_sheet.dart]
  — Hypothesis: on a ladder→ladder tier change that invalidates the current `reports_to` (e.g. Team
  Leader→Builder Head drops the head from valid managers), the `DropdownButtonFormField` would retain its
  internal `FormFieldState` value while the items list dropped it → "exactly one item" assertion. Wrote a
  targeted repro (`edit_sheet_regression_test.dart`): **no crash** — this Flutter SDK (3.44) re-seeds the
  field from `initialValue` on rebuild, and `_onTierChanged` clears the stale id in state first, so the
  rebuilt field lands on the `None` sentinel. Finding **refuted**; the repro is kept as a permanent
  regression guard.
- [ ] [Review][Low][No-fix] Agencies load-error degrades silently to an empty list in the edit sheet
  [organization_screen.dart] — `agenciesAsync.asData?.value ?? []` means a *failed* agencies fetch is
  indistinguishable from *no agencies* when editing a partner (shows "No agencies yet"). In practice the
  `agencies` read shares the same tenant RLS as `users`, so if the user list loaded the agencies list did
  too; a partial failure is a rare, non-blocking cosmetic case. Left as-is (parity with admin, which also
  treats a null result as empty). Noted for honesty.

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia / bmad-dev-story)

### Debug Log References

- `dart run build_runner build --delete-conflicting-outputs` → 2 new outputs
  (hierarchy_repository.g.dart, hierarchy_providers.g.dart).
- `flutter analyze lib` → 0 errors (247 pre-existing `info` const-hint lints in unrelated files;
  `features/hierarchy` + touched files analyze clean).
- `flutter test test/features/hierarchy` → 17/17. Full suite `flutter test` → **192/192** (was 175/175;
  +17 hierarchy tests).

### Completion Notes List

- New additive domain `features/hierarchy/{data,providers,ui}` mirroring Slice 1's `features/inventory`.
  No backend touched; consumes the shipped `set_user_hierarchy` RPC (0059) + the tenant-scoped `users` /
  `agencies` table reads (0057 RLS) the admin /hierarchy page uses.
- **RPC is authoritative (AC2/AC7):** the client never mutates `users` for hierarchy; it calls
  `set_user_hierarchy` and re-fetches through `fetchUsers()`. Every rejection maps via
  `HierarchyException.friendly` to a calm sentence (AC5) — no PostgREST dump.
- **Manager-options filter (AC3):** pure `managerOptionsFor()` returns only strictly-higher **ladder**
  users (excl. self); off-ladder tiers hide the reports-to field entirely. Mirrors the admin
  `managerOptions` logic; unit-tested across rep/leader/head/partner.
- **Partner-needs-agency (AC4):** client blocks save before the repo call; the RPC's
  `agency_required_for_partner` is the server backstop. Agencies list + inline create (AC6) insert into
  `agencies` passing `tenant_id` from the session (the column has no default; RLS `WITH CHECK` requires it).
- **Entry gate (AC7):** the WORKSPACE "Organization" row shows only when `appMetadata['role']=='admin'`
  (builder-head ≡ admin) — cosmetic only; `role_tier` is NOT trusted client-side (may be absent from JWT).
  A leaked screen mutates nothing (RPC re-checks `role='admin'` → `permission_denied`).
- **Verified on local Docker (2026-07-11)** via simulated-JWT SQL against the demo seed (all rolled back):
  1. head reads **5** active users = his tenant only (`rahul.acme` in another tenant NOT visible → RLS
     isolation confirmed).
  2. rep→receptionist reports_to → `reports_to_must_be_higher_tier`.
  3. partner w/o agency → `agency_required_for_partner`.
  4. receptionist w/ reports_to → `off_ladder_tier_has_no_reports_to`.
  5. non-admin (reception) caller → `permission_denied`.
  6. happy: head sets rep→head reports_to → json row returned.
  7. happy: head flips rep→partner_agency + Skyline → `is_external=true`, agency set.
  8. head `agencies` INSERT under RLS `WITH CHECK` → 1 row.
  The client wiring (users select, agencies insert, set_user_hierarchy round-trip) + every friendly-error
  path is thereby exercised end-to-end. On-device visual look-pass (pill colours/spacing) still to be
  eyeballed by Rudra — same posture as Slice 1.

### File List

**New**
- apps/mobile/lib/features/hierarchy/data/models/hierarchy_user.dart
- apps/mobile/lib/features/hierarchy/data/models/agency.dart
- apps/mobile/lib/features/hierarchy/data/hierarchy_repository.dart
- apps/mobile/lib/features/hierarchy/data/hierarchy_repository.g.dart (generated)
- apps/mobile/lib/features/hierarchy/providers/hierarchy_providers.dart
- apps/mobile/lib/features/hierarchy/providers/hierarchy_providers.g.dart (generated)
- apps/mobile/lib/features/hierarchy/ui/tier_pill.dart
- apps/mobile/lib/features/hierarchy/ui/edit_hierarchy_sheet.dart
- apps/mobile/lib/features/hierarchy/ui/organization_screen.dart
- apps/mobile/test/features/hierarchy/hierarchy_user_test.dart
- apps/mobile/test/features/hierarchy/hierarchy_exception_test.dart
- apps/mobile/test/features/hierarchy/edit_hierarchy_sheet_test.dart
- apps/mobile/test/features/hierarchy/edit_sheet_regression_test.dart (added during review — dropdown guard)

**Modified**
- apps/mobile/lib/router/app_router.dart (import + `/organization` route)
- apps/mobile/lib/features/home/ui/you_screen.dart (admin-gated WORKSPACE "Organization" row)

## Change Log

- 2026-07-10: Story drafted (bmad-create-story) — mobile hierarchy-management UI slice of 12.4.
- 2026-07-11: Implemented `features/hierarchy` — Organization screen (user list + tier pills), edit sheet
  → set_user_hierarchy, agencies list + inline create. 17 new tests; analyze 0 errors; full suite
  192/192. Guards + happy paths verified live on local Docker (simulated JWT). Status → review.
- 2026-07-11: Code review (3 lenses inline) — 0 confirmed findings; 1 suspected dropdown-crash
  investigated + refuted via a repro (kept as regression guard, +1 test → 193/193); 1 low no-fix
  observation. Status → done.
- 2026-07-11 (during 12-6-mobile review): patched `organization_screen.dart` `onRefresh` to guard the
  awaited refetch in try/catch — same unguarded-refresh-await defect found in the 12.6 team screen applied
  here (a refetch error would otherwise throw out of the RefreshIndicator callback). No behaviour change on
  success; suite still green. Cross-referenced in 12-6-mobile-team-sandbox.md Review Findings.
