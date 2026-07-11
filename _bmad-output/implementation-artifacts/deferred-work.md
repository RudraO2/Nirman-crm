# Deferred Work

## Deferred from: code review of story 10-2-fullscreen-ringing-alarm (2026-05-30)

- **AC4 — iOS time-sensitive critical notification** — iOS uses the no-op scheduler (no ring, no notification). The epic's iOS path (time-sensitive critical local notification) is unimplemented. App ships Android-only today, so non-blocking. When an iOS build exists, route the iOS branch through `flutter_local_notifications` (`interruptionLevel: timeSensitive`/critical + sound), reusing `planFollowUpAlarms` output so AC5 holds. AC4 is **not-met**, not satisfied.
- ~~**Targeted per-lead alarm cancel (for Story 10.3)**~~ — **CLOSED by Story 10.3 (2026-05-30).** Superseded by the reconcile model: `cancelScheduledAlarms` (selective: future + non-snooze only) followed by a rebuild from `getMyLeads()` covers reschedule/complete/archive/reassign uniformly without per-lead id recompute. No targeted cancel needed.
- **Single-active-ring-screen guard** — multiple offsets firing in one `Alarm.ringing` emission stack multiple `/alarm-ring` screens; the in-memory `_shown` set re-pushes a still-ringing alarm after a process relaunch. Add a guard that only one ring screen is shown at a time (queue or replace).
- **Log alarm decode failures / foreign-alarm path** — `FollowUpAlarmPayload.tryDecode` returning null and the "ring natively, no UI" branch in app.dart are silent; add a structured log so corruption/foreign alarms are observable.

## Deferred from: Story 5.2 — Per-Employee Performance Dashboard (2026-05-28)

- **Custom date range picker on Performance page** — The date range filter UI implements
  Today | Last 7 days | Last 30 days. The "Custom" option is deferred because it requires
  a date-picker library (date-fns or similar — not yet installed in apps/admin).
  `get_employee_performance_stats(p_days)` already accepts any integer, so the backend
  supports arbitrary windows. The UI work is purely frontend.
  **What's needed:** install `react-day-picker` or `date-fns` + add a custom range
  button + date picker popover that computes p_days from (today - selected_start) and
  navigates to `/performance?range=<p_days>` (or a custom param like `from`/`to`).

- ~~**D1 (ux): No loading skeleton on range-filter navigation**~~ **CLOSED 2026-07-11 (Amelia).**
  Added `apps/admin/src/app/(app)/performance/loading.tsx` (header + range chips + stat cards + table
  rows skeleton, `aria-busy`). Next 16 wraps `page.tsx` in Suspense automatically.

- ~~**D2 (accessibility): Toggle buttons + row clicks lack ARIA hints**~~ **CLOSED 2026-07-11 (Amelia).**
  Range buttons + both Show-All/More-columns toggles now carry `aria-pressed` (+ `aria-label`); the
  sortable "Active" header and every clickable employee row are now `role="button"` + `tabIndex={0}` +
  Enter/Space `onKeyDown` + `aria-label`/`aria-sort`.

- **D3 (minor): conversion_rate numeric coercion** — `get_employee_performance_stats`
  returns `conversion_rate numeric`. For employees with `total_assigned = 0`, the SQL
  returns NULL (ROUND(…/NULLIF(0,0), 1)). PostgREST maps NULL → null in JSON, which
  the UI displays as "—". Verified correct. No fix needed — noted for future type
  tightening (change TypeScript type to `number | null`).

## Deferred from: code review of story-5.3 (2026-05-28)

- ~~**F-1 (security): NULL JWT role check in `get_funnel_stats`**~~ **ALREADY RESOLVED — verified 2026-07-11
  (Amelia).** Migration `0054` (harden_admin_role_guards, 2026-05-29 — the day after this note) already
  migrated the codebase to the safe `IS DISTINCT FROM 'admin'` form. Confirmed on PROD: a catalog sweep for
  `<> 'admin'` / `!= 'admin'` across all SECURITY DEFINER functions returns **zero**, and `get_funnel_stats`
  now reads `IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN RAISE`. No migration
  needed.

- **F-2 (semantics): `p_days=1` ("Today") includes yesterday** — `(created_at AT TIME ZONE v_tz)::date >= v_today - 1` returns leads from the last 2 days (yesterday + today), not just today. This is consistent with the same pattern used in `get_employee_performance_stats` (0049) and matches the spec `p_days = N → created_at >= v_today - N`. A proper "Today only" filter would use `= v_today`. Deferring to avoid diverging from codebase convention; fix in a dedicated date-filter cleanup story that also adjusts 0049.

- ~~**F-3 (ux): No loading skeleton on filter navigation for Funnel page**~~ **CLOSED 2026-07-11 (Amelia).** Added `apps/admin/src/app/(app)/funnel/loading.tsx` (header + filter chips + tapered funnel-bar skeleton, `aria-busy`).

- ~~**F-4 (accessibility): Filter selects and range buttons lack ARIA labels**~~ **CLOSED 2026-07-11 (Amelia).** The employee + project `<select>`s now have `aria-label`; the range toggle buttons now carry `aria-pressed` + `aria-label`.

## Deferred from: Story 6.1 — Excel Bulk Import (2026-05-28)

- **D-6.1-1 (ux): No "Back" navigation in import wizard** — `import-wizard.tsx` is forward-only. Once on Preview or Assign, user cannot return to Map without restarting the file upload. Fix: add Back button to each step; restore prior state on back navigation (mappings, preview result).

- ~~**D-6.1-2 (security): xlsx@0.18.5 has known vulnerabilities**~~ **ALREADY DONE (Story 8.7) — verified
  2026-07-11 (Amelia).** `xlsx` is removed from `apps/admin` (not in package.json); the import path uses
  `exceljs@^4.4.0` via `src/app/(app)/import/xlsx-read.ts` (`readSheetGrid`, byte-for-byte parity with the
  old `sheet_to_json` behavior, parity tests in `parse.test.ts`). The high-severity `xlsx` CVEs
  (GHSA-4r6h-8v6p-xvw6 prototype-pollution, ReDoS) are gone. No work needed.

- ~~**D-6.1-3 (ux): No loading skeleton for /import route**~~ **CLOSED 2026-07-11 (Amelia).** Added `apps/admin/src/app/(app)/import/loading.tsx` (header + dropzone + button skeleton, `aria-busy`).

## Deferred from: code review of 8-1-harden-admin-role-guards (2026-05-29)

- **"Active lead" status filter formulated two opposite ways** — `get_employee_active_lead_count` uses `status NOT IN ('dead','sold','future')`, `get_employee_active_lead_counts` uses `status IN ('hot','warm','cold')`, `get_employee_performance_stats` uses NOT IN. Coincide only while the status enum stays exactly {hot,warm,cold,dead,sold,future}. Pre-existing (0054 faithfully reproduced prior bodies); harmless today. Pick one canonical formulation if the enum ever grows.
- **`permission_denied` raised without `ERRCODE='42501'`** in 6 inline-jwt admin fns (`get_builder_home_metrics`, `get_employee_activity_stats`, `get_employee_performance_stats`, `get_funnel_stats`, `get_lead_status_distribution`, `get_pipeline_activity_14d`). Callers keying on SQLSTATE 42501 won't catch these. Pre-existing; standardize ERRCODE across all admin guards in a future cleanup migration.

## Deferred from: code review of 8-2-tenant-lifecycle-status-trial (2026-05-29)

- **`auth_tenant_id()` reads `public.tenants` on every RLS evaluation** — Story 8.2 redefined the chokepoint to gate on `tenants.status`. It is `STABLE` (planner folds per-query in most plans) and the read is a single PK lookup on a 1-row-per-tenant table, so absolute cost is tiny today. At large tenant scale / hot query paths, revisit: options include caching `status` in the JWT `app_metadata` (requires re-issuing JWTs on status change) or a per-statement memoization. No action needed now.
- **8.3 `signup-create-tenant` ordering** — the new lifecycle gate means `auth_tenant_id()` returns NULL until the tenant row exists AND is `trial`/`active`. The 8.3 atomic-provisioning fn must (a) create the `tenants` row with `status='trial'` (an allowed status) and (b) not depend on `auth_tenant_id()` resolving mid-transaction before that row is committed. Use the service-role client (RLS-bypassing) for provisioning, as `bootstrap-admin` already does. Carry into the 8.3 story spec.

## Deferred from: code review of story 9-1-prepaid-access-gating-seam (2026-07-10)

- **Migration 0088 numeric ordering vs 0087:** 0088 (prepaid billing) was authored before 0087 (reserved by Story 8.3 harden-edge-function-auth, in-review). When 8.3 lands 0087 and `supabase db push --linked` runs, supabase will apply 0087 after 0088 is already in history (out of numeric order). Independent migrations so no dependency break, but coordinate the two deploys. Not a code defect.

## Deferred from: code review of 14-3-mobile-availability-grid (2026-07-10)

- ~~**Partner project-picker over-lists (AC3 scope nuance).**~~ **CLOSED 2026-07-11 (Amelia).**
  Fixed by migration **`0095` `get_my_projects()`** (per-tier scoped: partner_agency → agency-shared
  projects only; every other tier → all active tenant projects, identical to the old read) +
  `lead_repository.fetchProjects()` swapped from the direct `.from('projects')` read to the RPC. Scopes
  the picker across leads/inventory/booking in one place. Verified per-tier via sim-JWT on local Docker
  (head/super_admin=2 projects, partner=1). ✅ `0095` PUSHED TO PROD 2026-07-11 (with 0093/0094, head=0095).
  Original note kept below for context.

- **Partner project-picker over-lists (AC3 scope nuance).** The mobile Availability picker
  (`apps/mobile/lib/features/inventory/ui/inventory_projects_screen.dart`) lists ALL active tenant
  projects to every user via `availableProjectsProvider` (projects RLS is tenant-scoped). A
  `partner_agency` user therefore sees project *names* they can't open (grid RPC denies non-shared
  projects with a friendly empty state; units + margin stay fully scoped). Not fixable purely
  client-side because `role_tier` may be absent from the JWT (12.3 backfill not run) → cannot detect
  partner tier reliably. **Correct fix:** a backend `get_my_projects()` RPC scoping the project list
  per role tier the way `get_project_units` scopes units. Out of the internal-only demo path (§13.7).

## Deferred from: code review of 15-2-mobile-hold-unit (2026-07-10)

- ~~**Hold lead-picker is caller-own-leads only.**~~ **CLOSED 2026-07-11 (Amelia).** NO new backend
  needed — the team-scoped read `get_team_leads` already exists on prod (migration `0060`, scoped by
  `visible_user_ids()`). `hold_lead_picker_sheet.dart` now watches `teamLeadsProvider` (+ `ownerNamesProvider`
  for per-row owner labels) instead of `myLeadsProvider`, so head=all / leader=subtree / rep=self —
  exactly `hold_unit`'s allow-set. (A rep's owned set is unchanged; only peer-SHARED leads drop, and
  `hold_unit` rejects those anyway, so nothing holdable is lost.) 2 widget tests added; suite 265/265,
  analyze 0 errors. Original note kept below.

- **Hold lead-picker is caller-own-leads only.** `hold_lead_picker_sheet.dart` reuses `myLeadsProvider`.
  The `hold_unit` RPC also allows builder_head (any tenant lead) and team_leader (visible subtree), so a
  head/leader can only hold via UI for a lead they personally own. Acceptable (holding is a rep action);
  widening needs a team-scoped lead read (Story 12.5-mobile / get_team_leads).

## 15.5-mobile — agent-level filter on booking dashboard (~~deferred 2026-07-11~~ CLOSED 2026-07-11, Amelia)
**CLOSED.** Correction to the original note: only `get_active_holds` took `p_agent_id` (0079);
`get_booking_stats` did NOT — so migration **`0096`** adds `p_agent_id` to `get_booking_stats` (DROP+CREATE
to avoid an overload; `visible_user_ids()` scope gate preserved, so an out-of-scope agent id → empty, no
leak). No separate roster picker was needed: the agent roster is derived from the active holds themselves
(distinct `holding_agent_id` + `agent_name`, already returned + visibility-scoped), shown only when >1
agent has holds. Dashboard: agent chips + client-side list filter + server-side stats via the new param;
switching project resets the agent filter. Verified per-agent via sim-JWT (head all=3/2/1/33.3%, agent-e1
2/1/1/50%, agent-self 1/1/0/0%) + 2 new widget tests. Suite **267/267**, analyze 0 errors. ✅ **`0096`
pushed to prod 2026-07-11 (head now 0096, signature confirmed).**

## 16.2-mobile — rep-facing amendment log entry + 16.4 push (deferred 2026-07-11)
- ~~**Rep log entry:**~~ **CLOSED 2026-07-11 (Amelia).** No backend change needed — the held-unit detail
  sheet already reads the active hold (`activeHoldProvider` → `hold.leadId`), so `unit_detail_sheet.dart`
  now shows a "Log amendment" action below Confirm on a held unit, opening the existing `showLogAmendmentSheet`
  with the held lead. `log_amendment` (0081/0084) stays authoritative (who may log + lead↔unit link); the
  UI shows calm guard errors. Widget test added (held unit → Confirm + Log amendment).
- **16.4 FCM push/deep-link (STILL DEFERRED):** the amendment notify edge fn (`send-amendment-notification`,
  0083) is dormant/undeployed; in-app destinations exist but push delivery + deep-link routing are not
  wired. Follow-up when the edge fn is deployed + a caller drains `domain_events` (needs Rudra to deploy the fn).
- ~~**Non-head execution-member entry:**~~ **CLOSED 2026-07-11 (Amelia).** The `tenant_execution_team`
  SELECT policy already lets any tenant member read it, so a cheap client membership read
  (`AmendmentsRepository.isExecutionMember` → `isExecutionMemberProvider`, fail-soft to false) now widens
  the You-tab "Amendments" gate to `role == 'admin' || isExecMember`. No JWT-claim change, no backend change;
  the screen + RPCs still re-guard server-side.
