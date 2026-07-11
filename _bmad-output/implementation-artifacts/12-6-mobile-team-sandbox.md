---
baseline_commit: 596238c1176640da3f0b37b089fb220fab4ad2ac
---
# Story 12.6-mobile: partner sandbox & team-scoped lead visibility (Flutter UI)

Status: done

<!-- Mobile-UI slice covering the deferred mobile surface of Stories 12.5 + 12.6. The backend
(migration 0060 visible_user_ids() + get_team_leads; 0061 receptionist gate-not-own; partner agency
scoping) is DONE on prod — do NOT touch it. This story ships ONLY the mobile "Team" leads view that
consumes get_team_leads, correctly scoped per tier by the RPC, plus the partner-sandbox / receptionist
empty-state behaviour. Named `12-6-mobile-*` to preserve the 12-6 backend record. Slice 2 of the mobile
builder-ops build. -->

## Story

As a Team Leader (or Builder Head, or Partner),
I want to see the leads across my visibility scope on my phone with each lead's owner,
so that I can monitor and coach my team (or track my agency's leads) without losing rep-level isolation.

## Acceptance Criteria

1. **Given** the shipped `get_team_leads(limit, offset)` **When** I open the Team screen **Then** it lists
   the leads the RPC returns for my tier — a `team_leader` sees their reporting subtree, a `builder_head`
   sees all internal leads, a `partner_agency` sees only their agency's leads, and each row shows the
   lead's owner. The RPC is the single source of truth for scope; the client never filters leads itself.
2. **And** a `front_line_rep` calling the Team screen sees exactly their own leads (the RPC's
   `visible_user_ids()` = self) — identical to My Leads, so the entry is not surfaced to plain reps.
3. **And** a `receptionist` (gate-not-own) who reaches the screen sees a calm empty state (their visible
   set owns no leads), never a crash — and the entry is not surfaced to them.
4. **And** a `partner_agency` user never sees internal leads through this screen: only agency-scoped rows
   are returned (RPC-enforced), and owner names shown are only those of the returned leads' owners (no
   internal roster is rendered), preserving the sandbox.
5. **And** tapping a lead opens the existing read-only lead detail; the Team screen ships NO lead-mutation
   path (monitoring only — coaching, not editing).
6. **And** the Team entry is shown only to tiers that benefit (best-effort client gate on `role='admin'`
   or a `role_tier` of `team_leader`/`partner_agency`); the RPC scopes correctly regardless, so a leaked
   entry is safe (a rep just sees their own; a receptionist sees empty).

## Tasks / Subtasks

- [ ] **Task 1 — Data layer** (`features/team/data/`) (AC: 1,4)
  - [ ] `models/team_lead.dart`: `TeamLead` = the existing `LeadListItem` (reused from
        `features/leads/data/models/lead_model.dart`) + `ownerId` (String?, from `assigned_to_user_id`).
        `fromJson` delegates to `LeadListItem.fromJson(j)` then reads `assigned_to_user_id`. Note
        `get_team_leads` omits `interest_type`/`archived_at`/`is_shared` → those map to null/false safely.
  - [ ] `team_repository.dart`: `TeamRepository(SupabaseClient)`:
        - `Future<List<TeamLead>> getTeamLeads({int limit = 100, int offset = 0})` →
          `.rpc('get_team_leads', params: {'p_limit', 'p_offset'})`. Map `PostgrestException` to a typed
          `TeamAccessException` (mirror `InventoryAccessException.fromPostgrest`); `not_authenticated` →
          a calm sign-in message; else generic. (The RPC returns an empty set — not an error — for
          receptionist/self-only, so empty is the normal calm path, not an exception.)
        - `Future<Map<String, String>> fetchOwnerNames(Set<String> ownerIds)` → `.from('users').select(
          'id, email_or_username').inFilter('id', ids)` for ONLY the ids present in the returned leads
          (never the whole roster — keeps the partner sandbox intact). Returns id→display map.
        - Expose `@riverpod TeamRepository teamRepository(...)`.
- [ ] **Task 2 — Providers** (`features/team/providers/`) (AC: 1)
  - [ ] `teamLeadsProvider` (`@riverpod Future<List<TeamLead>>`) → repo `getTeamLeads()`.
  - [ ] `ownerNamesProvider` (`@riverpod Future<Map<String,String>>`) that watches `teamLeadsProvider`,
        collects the distinct non-null `ownerId`s, and calls `fetchOwnerNames`. Fail-soft: on error return
        an empty map (owner falls back to a masked label — never blocks the list).
  - [ ] Run `dart run build_runner build --delete-conflicting-outputs`.
- [ ] **Task 3 — UI** (`features/team/ui/`) (AC: 1,3,4,5)
  - [ ] `team_leads_screen.dart`: AppBar "Team leads"; loading / error / empty. Empty state is calm and
        tier-agnostic ("No team leads to show yet."). Each row: lead name (or phone), a status pill (reuse
        the leads status colour tokens / `AppColors`), an owner chip (resolved name, else "Teammate" +
        short id), and the urgency/last-action hint. Pull-to-refresh invalidates `teamLeadsProvider`.
        Tapping a row → `context.push('/lead/${lead.id}')` (existing read-only detail). NO swipe/mutation
        actions (monitoring only).
  - [ ] Entry point: add a "Team leads" row to the WORKSPACE group in `you_screen.dart`, shown when
        `role == 'admin'` OR `appMetadata['role_tier']` ∈ {`team_leader`,`partner_agency`}. Add a
        top-level `GoRoute('/team-leads')` in `router/app_router.dart`. Append only — do not touch the
        auth/billing redirect logic.
- [ ] **Task 4 — Tests** (`test/features/team/`) (AC: 1,2,4)
  - [ ] `TeamLead.fromJson` maps a full get_team_leads row incl. `assigned_to_user_id` → `ownerId`, and
        tolerates the omitted `interest_type`/`is_shared` keys.
  - [ ] `TeamAccessException` mapping: `not_authenticated` → sign-in message; unknown → generic.
  - [ ] Owner-id collection logic (pure): distinct non-null owner ids from a lead list (drives the
        bounded `fetchOwnerNames` call — proves we never fetch the whole roster).
  - [ ] Widget/logic test: the screen renders an owner chip using the resolved name and falls back to a
        masked label when the name map lacks the id.
  - [ ] Keep `flutter analyze` at 0 errors and the full mobile suite green.
- [ ] **Task 5 — Verify scope live on local Docker** (AC: 1,2,3,4)
  - [ ] With the demo seed applied, run simulated-JWT `get_team_leads` for each tier and record the row
        counts + that partner rows are agency-only and receptionist is empty (pattern below). Confirm the
        client renders exactly the RPC's scope.

## Dev Notes

### The backend contract (already shipped — do NOT modify)
`get_team_leads(p_limit int DEFAULT 100, p_offset int DEFAULT 0)` — SECURITY DEFINER, `authenticated`
only. RETURNS the `get_my_leads` column set **plus `assigned_to_user_id`**, urgency-sorted, PII-decrypted,
scoped to `assigned_to_user_id IN (SELECT user_id FROM visible_user_ids())`. It does NOT raise on an empty
scope — a receptionist / self-only rep simply gets fewer/zero rows. `visible_user_ids()`:
builder_head/super_admin → whole internal tree; team_leader → reporting subtree; partner_agency → own
agency's users; rep/receptionist → self. Fail-closed on missing context.
[Source: nirman-crm/supabase/migrations/0060_visibility.sql; 12-5-hierarchical-lead-visibility.md,
12-6-partner-sandbox-receptionist-provisioning.md]

`get_my_leads` is UNCHANGED and remains the rep's My Leads source — do not reroute reps through
get_team_leads. This screen is additive.

### Why owner-name resolution is sandbox-safe
`users_select` (0003) lets ANY authenticated tenant member read user rows (id + name) in their tenant —
so name resolution works for every tier. To keep the partner sandbox intact, resolve names ONLY for the
owner ids that appear in the caller's returned leads (a partner's returned leads are all agency-owned, so
no internal name is ever fetched or shown). Never render the full roster on this screen.
[Source: nirman-crm/supabase/migrations/0003_cr_patch_jwt_only_rls.sql]

### Role on the client (why the entry gate is best-effort)
`appMetadata['role']` is present (`'admin'` for head/super). `role_tier` MAY be absent from the JWT (12.3
backfill not run in prod) — in the demo seed it IS stamped (raw_app_meta_data), so leader/partner see the
entry there. Gate the entry on `role=='admin' || role_tier ∈ {team_leader, partner_agency}`; if role_tier
is absent for a leader in prod they simply won't see the entry (acceptable cosmetic degradation — the RPC
still scopes correctly if reached). NEVER gate correctness on client role_tier. [Source: project-state.md;
nirman-crm/CLAUDE.md; you_screen.dart]

### Reuse, don't reinvent
- Reuse `LeadListItem` + its `fromJson` (leads feature) for the lead body — get_team_leads returns a
  superset of its columns. Only add `ownerId`.
- Reuse the status-colour tokens already used by the leads list (`AppColors` / the lead status extension
  in `lead_model`/`app_theme`) — do not invent a second palette.
- Route to the EXISTING `/lead/:id` detail screen; do not build a new detail.
- Structure mirrors `features/inventory` / `features/hierarchy`: `data/{models/},providers/,ui/`; repo =
  plain class + `@riverpod`; models immutable `fromJson`; typed exception from `PostgrestException`;
  top-level GoRoute. [Source: features/inventory/*, features/hierarchy/* (Slice 1 & 2 patterns)]

### Testing standards
`flutter test` under `test/features/team/`. Unit-test pure logic (fromJson, exception mapping, owner-id
collection) without a live Supabase; fake the repo for widget/provider tests. 0 `flutter analyze` errors,
full suite green. [Source: nirman-crm/CLAUDE.md]

### Local test env (FREE — never prod)
Docker Supabase up; demo seed `supabase/demo-builder-ops.local.sql`. Verify scope per tier:
```sql
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub":"<uid>","app_metadata":{"role":"<role>","tenant_id":"00000000-0000-0000-0000-000000000001","role_tier":"<tier>"}}';
  select count(*), count(distinct assigned_to_user_id) from get_team_leads(500,0);
rollback;
```
Run for head (all internal), leader (subtree), partner (agency-only), receptionist (0), rep (self).
[Source: project-state.md §Demo seed]

### Project Structure Notes
- New domain `features/team` is additive; only `you_screen.dart` (one WORKSPACE row) + `app_router.dart`
  (one route) are modified. Preserve the 3-tab shell + auth/billing redirects — append only.
- No new migration, no backend change. If you find yourself editing anything under `supabase/`, STOP.

### References
- [Source: epics.md#Story 12.5, #Story 12.6]
- [Source: architecture-builder-ops-v2.md §2.2 visible_user_ids, §13.2 partner matrix, §14.1 routing]
- [Source: nirman-crm/supabase/migrations/0060_visibility.sql, 0061_partner_receptionist_guards.sql, 0003_cr_patch_jwt_only_rls.sql]
- [Source: 12-5-hierarchical-lead-visibility.md, 12-6-partner-sandbox-receptionist-provisioning.md (backend records — the deferred mobile view is this story)]
- [Source: nirman-crm/apps/mobile/lib/features/leads/data/models/lead_model.dart (LeadListItem reuse)]
- [Source: nirman-crm/apps/mobile/lib/features/inventory/*, features/hierarchy/* (repo+provider+exception+router pattern)]
- [Source: nirman-crm/apps/mobile/lib/features/home/ui/you_screen.dart; router/app_router.dart]

## Review Findings

_Code review 2026-07-11 (3 lenses inline: Blind Hunter / Edge-Case Hunter / Acceptance Auditor).
**1 confirmed finding (patched), 1 style fix, 0 outstanding.** ACs 1–6 satisfied; RPC-scoped visibility,
sandbox-safe owner resolution, read-only routing, and calm empty state verified. Full suite 204/204,
analyze 0 errors._

- [x] [Review][Patched] **Unguarded `await` in `RefreshIndicator.onRefresh` throws on a refetch error**
  [team_leads_screen.dart] — `onRefresh` did `ref.invalidate(...)` then `await ref.read(provider.future)`
  with no catch. If the refetch fails (transient network / RLS hiccup), the future completes with an error
  and awaiting it rethrows **out of the refresh callback** as an unhandled async error (Slice 1's grid
  sidesteps this by being invalidate-only). Wrapped the await in `try/catch` (error is already rendered by
  the `.when` error branch, so it's swallowed) — keeps the nicer "spinner holds until data lands" UX
  without the throw. **The same pattern existed in Story 12.4's `organization_screen.dart` (also written
  this Slice) — patched there too** (see that story's Change Log).
- [x] [Review][Patched][Style] `ownerNamesProvider` used `ref.watch` for the stable `teamRepository` past
  an `await` [team_providers.dart] — switched to `ref.read` (the repo never changes; watching after an
  await point is the documented anti-pattern). The intended dependency — `teamLeadsProvider.future` — is
  still `ref.watch`ed, so the names correctly re-resolve when the lead list changes.

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia / bmad-dev-story)

### Debug Log References

- `dart run build_runner build --delete-conflicting-outputs` → 2 new outputs (team_repository.g.dart,
  team_providers.g.dart).
- `flutter analyze lib` → 0 errors (`features/team` + touched files clean).
- `flutter test test/features/team` → 11/11. Full suite `flutter test` → **204/204** (was 193; +11 team).

### Completion Notes List

- New additive domain `features/team/{data,providers,ui}` mirroring Slice 1/2. No backend touched;
  consumes the shipped `get_team_leads` RPC (0060) + a bounded `users` name read (0003 RLS).
- **RPC-authoritative scope (AC1/AC2):** the client never filters leads; `get_team_leads` scopes via
  `visible_user_ids()`. `TeamLead` reuses `LeadListItem.fromJson` (get_team_leads returns a superset of
  get_my_leads' columns; omitted `interest_type`/`is_shared` map to null/false) + adds `ownerId`.
- **Sandbox-safe owner names (AC4):** `ownerNamesProvider` resolves names for ONLY the distinct owner ids
  present in the returned leads (`distinctOwnerIds`), never the whole roster — so a partner (whose returned
  leads are all agency-owned) never fetches or renders an internal name. Fail-soft to a masked
  "Teammate ·xxxx" label so a load error never blocks the list.
- **Read-only (AC5):** rows route to the existing `/lead/:id` detail; no swipe/mutation path (monitoring).
- **Empty = calm, not error (AC3):** the RPC returns zero rows (not an exception) for receptionist /
  self-only; the screen shows "No team leads to show yet."
- **Best-effort entry (AC2/AC6):** the WORKSPACE "Team leads" row shows when `role=='admin'` OR
  `role_tier ∈ {team_leader, partner_agency}`. `role_tier` is NOT trusted for correctness (may be absent
  from JWT in prod → a leader there just won't see the entry; RPC still scopes if reached). Reps/reception
  don't see it (rep already has My Leads; reception owns nothing).
- **Verified on local Docker (2026-07-11)** via simulated-JWT `get_team_leads` against the demo seed
  (leads live on rep1=3 and super_admin=1; partner's agency has none):
  - builder_head → 3 rows / 2 owners (all internal, incl. the super_admin's lead).
  - super_admin → 3 / 2 (whole internal tree, matches head).
  - team_leader (as rep1, no reports) → 2 / 1 (subtree = self).
  - front_line_rep (rep1) → 2 / 1 (self only — AC2).
  - **partner_agency → 0 rows (agency has no leads; NO internal leak — AC4).**
  - **receptionist → 0 rows (gate-not-own — AC3).**
  head's breadth (3) strictly exceeds a rep's (2), confirming the tree vs self scoping. The client renders
  exactly the RPC's scope. On-device visual look-pass (pills/owner chips) still to be eyeballed by Rudra.

### File List

**New**
- apps/mobile/lib/features/team/data/models/team_lead.dart
- apps/mobile/lib/features/team/data/team_repository.dart
- apps/mobile/lib/features/team/data/team_repository.g.dart (generated)
- apps/mobile/lib/features/team/providers/team_providers.dart
- apps/mobile/lib/features/team/providers/team_providers.g.dart (generated)
- apps/mobile/lib/features/team/ui/team_leads_screen.dart
- apps/mobile/test/features/team/team_lead_test.dart
- apps/mobile/test/features/team/team_leads_screen_test.dart

**Modified**
- apps/mobile/lib/router/app_router.dart (import + `/team-leads` route)
- apps/mobile/lib/features/home/ui/you_screen.dart (best-effort-gated WORKSPACE "Team leads" row)

## Change Log

- 2026-07-11: Story drafted (bmad-create-story) — mobile team-scoped lead visibility + partner sandbox
  slice of 12.5/12.6.
- 2026-07-11: Implemented `features/team` — "Team leads" screen via get_team_leads (RPC-scoped), bounded
  sandbox-safe owner resolution, read-only detail routing. 11 new tests; analyze 0 errors; full suite
  204/204. Scope verified live per tier on local Docker (partner=0, receptionist=0). Status → review.
- 2026-07-11: Code review (3 lenses inline) — patched 1 confirmed defect (unguarded refresh-await throw;
  fixed in this screen AND in 12.4's organization_screen) + 1 style fix (ref.read past await). Suite
  204/204, analyze 0. Status → done.
