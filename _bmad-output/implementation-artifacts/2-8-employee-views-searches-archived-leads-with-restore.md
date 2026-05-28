# Story 2.8: Employee views and searches archived leads with restore

Status: ready-for-dev

> **Provenance**: not in epics.md; created 2026-05-28 to close the **FR-16** view/search/restore gap left by Story 2.7. Story 2.7 implemented the *move-to-archived* logic (`is_archived` derived from status); the Archived **view** itself was never built on mobile, so an employee who marks a Lead Sold/Dead/Future cannot find or restore it. This story closes the loop on Epic 2's lifecycle by giving employees a way to see, search, and restore archived leads. Reopens `epic-2` to `in-progress` until 2.8 ships.

## Story

As an Employee,
I want to view, search, and restore my Dead / Sold / Future leads from an Archive screen,
so that I can recover a wrongly archived lead, look up past closes, and never lose a lead.

## Acceptance Criteria

1. **Given** I am on the Home screen **When** I tap the Archive icon in the AppBar **Then** the Archive screen opens (`/archived`).
2. The Archive lists **only** my leads whose `status ∈ (dead, sold, future)` (i.e. exactly the leads excluded from the active list by `get_my_leads`). It is **caller-scoped** — no other employee's archived leads are reachable. (FR-16, FR-21)
3. Each row shows: lead name (decrypted), phone (last 4 digits), a status badge (`Dead` / `Sold` / `Future`), and the date the lead was archived (most recent `status_changed→{dead|sold|future}` event, tenant tz). Newest-archived first.
4. A search box at the top filters by **name substring** (case-insensitive, decrypted) and/or **exact phone** (input normalized via the same `normalize_phone` rules → matched against `phone_hash`). Empty query → full list.
5. Tapping a row opens the existing Lead Detail screen (`/lead/:id`) read-only-feeling (no restrictions — same as today).
6. Each row has a **Restore** action (trailing menu or long-press). Restore opens a small chooser with the three active statuses (Hot / Warm / Cold). Picking one calls `restore_lead(lead_id, picked_status)` → the lead is removed from the Archive, returns to the active list with the chosen status, and the Timeline records `status_changed` with `from = <previous archived status>` and `to = <picked>`.
7. Pagination: page size 50, infinite scroll. The query supports `p_limit` and `p_offset`.
8. Leads are **never deleted** (FR-16). Restore is the only way out of Archive (other than admin actions, out of scope for 2.8).
9. Performance: list renders ≤ 1.5s for tenants with up to 50,000 archived leads (NFR; matches active-list budget).

## Tasks / Subtasks

- [ ] **Task 1 — Migration `0035_get_my_archived_leads.sql`** (AC: 2,3,4,7,9)
  - [ ] `CREATE OR REPLACE FUNCTION public.get_my_archived_leads(p_q text DEFAULT NULL, p_limit int DEFAULT 50, p_offset int DEFAULT 0)` `RETURNS TABLE` matching the shape of `get_my_leads` (id, name, phone last 4, status, archived_at, plus the standard list-item columns the mobile model needs).
  - [ ] `LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions`. Mirror the PII-decrypt pattern from 0017 (qualified `s.name='lead_pii_key'` from `vault.decrypted_secrets s` per 0027 fix).
  - [ ] Filter: `assigned_to_user_id = auth.uid()` AND `status IN ('dead','sold','future')`.
  - [ ] `archived_at` = `max(t.occurred_at) FILTER (WHERE t.event_type='status_changed' AND t.payload->>'to' IN ('dead','sold','future'))` per lead; sort `archived_at DESC` (newest archive first), tiebreak `created_at DESC`.
  - [ ] Search: if `p_q IS NOT NULL AND length(trim(p_q)) > 0`:
    - **name match**: `pgp_sym_decrypt(name_encrypted, key) ILIKE '%' || trim(p_q) || '%'`
    - **phone match**: `phone_hash = encode(sha256(public.normalize_phone(trim(p_q))::bytea), 'hex')` when `normalize_phone(trim(p_q))` returns a value
    - combine with OR; if neither yields a match, list is empty (do not fall back to all).
  - [ ] `REVOKE … FROM PUBLIC, anon; GRANT … TO authenticated`. Apply via `supabase db push --linked`.

- [ ] **Task 2 — Migration `0036_fix_restore_lead_generic_from.sql`** (AC: 6)
  - [ ] **Bug**: `restore_lead` (0021) hardcodes `jsonb_build_object('from', 'dead', 'to', p_restore_status, 'restored', true)` so restoring from `sold` or `future` logs an incorrect `from`.
  - [ ] Fix: read the lead's CURRENT status before update into `v_prev`, then log `'from', v_prev::text`. Preserve existing ownership + auth checks. Keep signature unchanged.
  - [ ] Apply via `supabase db push --linked`. Verify with a probe query: previously-sold lead restored to `warm` → most recent `status_changed` payload has `from='sold'`.

- [ ] **Task 3 — Mobile data layer** (AC: 2,3,4,6,7)
  - [ ] Reuse `LeadListItem` model — confirm it has the fields the Archive row needs (`id`, `name`, `phoneLast4`, `status`, `nextFollowupAt`, etc.). If not, add `archivedAt: DateTime?` to the model with `fromJson` parsing.
  - [ ] `LeadRepository.getMyArchivedLeads({String? query, int limit=50, int offset=0})` → RPC call → list of `LeadListItem`. `restoreLead` already exists on the repo (used by mark-dead undo) — reuse it for restore. Wire `restoreLead(leadId, pickedStatus)` from Archive UI.
  - [ ] `@riverpod` family provider `archivedLeads(String query)` — keyed on query. Invalidate alongside `myLeadsProvider` on restore.

- [ ] **Task 4 — UI: Archive screen** (AC: 1,2,3,4,5,6,9)
  - [ ] New file `apps/mobile/lib/features/leads/ui/archived_screen.dart` (`ArchivedScreen` `ConsumerStatefulWidget`).
  - [ ] AppBar: title "Archive", back button.
  - [ ] Sticky search `TextField` at top, debounced 300ms; updates the provider key.
  - [ ] Body: paginated list (`ListView.builder` + scroll listener for next-page fetch). Each row = `LeadCard` (existing) **with**: status badge (Dead red / Sold green / Future amber) and a trailing `PopupMenuButton` with one item "Restore…".
  - [ ] Tap row → `context.push('/lead/${lead.id}')`.
  - [ ] Restore tap → `showModalBottomSheet` with 3 chips (Hot, Warm, Cold) + Cancel. Pick → `await leadRepository.restoreLead(id, picked)` → invalidate `archivedLeadsProvider` + `myLeadsProvider` + `myMotivationStatsProvider` + `myMonthlyBestProvider` → SnackBar "Restored to Hot." (or chosen).
  - [ ] Empty state (no leads): "No archived leads yet." Search-empty state: "No matches for '<q>'."
  - [ ] Loading: skeleton (reuse `_SkeletonCard` style).
  - [ ] Error: terse error view with retry.

- [ ] **Task 5 — Route + entry point** (AC: 1)
  - [ ] Add `GoRoute(path:'/archived', builder:(_, __) => const ArchivedScreen())` in `app_router.dart`.
  - [ ] Add an Archive `IconButton` (`Icons.inventory_2_outlined` or `Icons.archive_outlined`) to `home_screen` AppBar `actions` — placed before the existing calendar/settings icons. `onPressed: () => context.push('/archived')`. Tooltip "Archive".

- [ ] **Task 6 — Tests**
  - [ ] Live SQL probe (documented in Dev Agent Record): `get_my_archived_leads()` returns the test user's sold lead after we re-mark one sold then restore it; the timeline `from` field reflects the actual prior status (proves 0036 fix). Restore on completion.
  - [ ] Dart unit/widget: search debounce calls provider with trimmed query; restore action invalidates the right providers; status badge maps correctly for dead/sold/future.

## Dev Notes

### Files to touch
- **NEW** `supabase/migrations/0035_get_my_archived_leads.sql`
- **NEW** `supabase/migrations/0036_fix_restore_lead_generic_from.sql`
- **NEW** `apps/mobile/lib/features/leads/ui/archived_screen.dart`
- **UPDATE** `apps/mobile/lib/features/leads/data/lead_repository.dart` — add `getMyArchivedLeads`.
- **UPDATE** `apps/mobile/lib/features/leads/providers/lead_providers.dart` — add `archivedLeads(query)` family.
- **UPDATE** `apps/mobile/lib/features/leads/data/models/lead_model.dart` — add `archivedAt: DateTime?` to `LeadListItem.fromJson` (additive, nullable; backwards-compatible — existing `get_my_leads` doesn't return it, so `fromJson` must default to null).
- **UPDATE** `apps/mobile/lib/router/app_router.dart` — `/archived` route.
- **UPDATE** `apps/mobile/lib/features/home/ui/home_screen.dart` — Archive AppBar icon.
- After repo/provider changes, run `dart run build_runner build --delete-conflicting-outputs`.

### Architecture compliance
- **RPC pattern** — SECURITY DEFINER + `SET search_path = public, extensions` + `REVOKE … FROM PUBLIC, anon; GRANT … TO authenticated` [Source: existing 0017/0019/0027/0029/0030/0031/0034].
- **PII decrypt** — `pgp_sym_decrypt(name_encrypted, (SELECT decrypted_secret FROM vault.decrypted_secrets s WHERE s.name='lead_pii_key' LIMIT 1)::bytea)` — qualify `s.name` to avoid the 0027 ambiguity bug.
- **Tenant tz** for `archived_at` display only on the client; the RPC returns `archived_at` as `timestamptz` and the app formats in tenant tz (single-tz tenant in V1 → device tz is fine).
- **Phone search** — `phone_hash` is SHA-256 of normalized phone. Substring on phone is **impossible** by design. Only exact match (after `normalize_phone`) is supported. Document the UX expectation.
- **Visibility isolation** [FR-31] — `auth.uid()` gating in the RPC enforces caller-only access. No RLS bypass.

### Reusables — do NOT reinvent
- `restoreLead` in `LeadRepository` (used by mark-dead undo) — same signature, reuse.
- `restore_lead` DB function (0021) — fixed by 0036 for from-status correctness.
- `LeadCard` widget — render unchanged; add the status badge + trailing menu in a thin wrapper, not by editing the card.
- `_SkeletonCard` style from `home_screen.dart` — copy/extract if needed.
- `normalize_phone()` SQL fn — used by `get_my_archived_leads` for phone search.

### State management
- `archivedLeadsProvider(String query)` is a Riverpod **family** keyed on query string. Debounced search updates the key. Restore invalidates **all keys** via `ref.invalidate(archivedLeadsProvider)` (no arg → invalidates the family).

### Previous-story intelligence (Story 2.7)
- 2.7 introduced `markLeadDead` → status='dead' + `mark_dead` event; restore via existing `restore_lead`. The Archive UI is the natural counterpart Story 2.7 deferred. No 2.7 file in `_bmad-output/implementation-artifacts/` to read; details from epics.md line 433-455.

### Open questions resolved
- **Search: name AND phone, or one?** Allow both — name substring (decrypted) OR exact-phone (hash match). Combine with OR.
- **Restore target status** — explicit pick (Hot/Warm/Cold). Do not silently default; that would mask intent. Hot/Warm/Cold are the active statuses; restoring to Dead/Sold/Future is a no-op (same archive).
- **Future leads + Interest Type** — Story 4.6 (Future Pool, admin) handles the project-match reactivation flow. 2.8 just shows them as archived; no special handling required here.

### Testing standards
- 0 errors from `flutter analyze`. Full mobile suite green.
- Live RPC verified with the test user JWT before marking Status: review.

## Dev Agent Record

### Agent Model Used
claude-opus-4-7 (Amelia, bmad-agent-dev)

### Debug Log References

### Completion Notes List

- Story context created 2026-05-28. Reopens Epic 2 to close FR-16 view+search+restore gap. Ultimate context engine analysis completed — comprehensive developer guide created.

### Change Log

### File List
