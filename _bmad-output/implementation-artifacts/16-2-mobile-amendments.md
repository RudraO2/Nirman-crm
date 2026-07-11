---
baseline_commit: 596238c1176640da3f0b37b089fb220fab4ad2ac
---
# Story 16.2-mobile: amendments — log + execution status surface (Flutter UI)

Status: review

<!-- Mobile-UI completion of Epic 16 (Stories 16.2/16.3, with 16.4 notify context). Backend
(0080 schema, 0081 log_amendment, 0082 set_amendment_status + get_amendments_for_execution +
add/remove_execution_member, 0083 notify triggers + edge fn, 0084 lead_not_linked hardening) is DONE on
prod and recorded in 16-1..16-4 — do NOT touch it. This story is ONLY the deferred mobile surfaces:
(1) log an amendment against a held/sold unit for its lead (16.2, lead-Timeline link reused);
(2) the execution-team status surface (16.3, PII-minimized); (3) the in-app destinations for the 16.4
FCM notify (the actual push edge fn is dormant/undeployed — out of scope). Named `16-2-mobile-*` to
preserve the backend records. Slice 3 of the mobile builder-ops build. -->

## Story

As a salesperson (and an execution-team member),
I want to log a client's requested modification against their held/booked unit, and — if I'm on the
execution team — move amendments through their build status,
so that change requests are captured against the right unit + lead and the fit-out progress is tracked.

## Acceptance Criteria

1. **Given** an active hold on the booking dashboard **When** I tap "Log amendment" and enter a
   description **Then** the client calls `log_amendment(unit_id, lead_id, description)` (RPC-authoritative)
   and, on success, confirms; the amendment also appends to the linked lead's Timeline (backend dual-log,
   already surfaced as "Amendment logged" from 13-4-mobile).
2. **And** a `partner_agency` caller (`forbidden_role`), a non-hold/sold unit (`unit_not_amendable`), a
   lead outside visibility (`lead_not_visible`), an unlinked lead (`lead_not_linked_to_unit`), or an empty
   description (`description_required`) each map to a calm inline message — no red PostgREST dump.
3. **Given** I open the Amendments (execution) screen **When** I am on `tenant_execution_team` **Then** I
   see amendments for my tenant via `get_amendments_for_execution` (unit_no, configuration, description,
   status — **NO lead name/phone**, AC4 PII minimization) and can move each through its lifecycle
   (requested→acknowledged→in_progress→done, or →rejected from any non-terminal) via `set_amendment_status`.
4. **And** an invalid transition (`invalid_transition`) or a non-member caller (`not_execution_member`)
   maps to a calm message; the surface never shows lead PII.
5. **And** a Builder Head who is not yet on the execution team can add themselves (`add_execution_member`)
   from the screen, so the head can always reach the surface (16.3 Task 2). Non-head, non-member users see
   a calm "You're not on the execution team" state (membership is a table, not a JWT claim).
6. **And** the entry to the execution surface is best-effort gated to `role == 'admin'` (head); the RPCs
   re-check membership/tier server-side, so the gate is cosmetic only.

## Tasks / Subtasks

- [x] **Task 1 — Data layer** (`features/amendments/data/`) (AC: 1,2,3,4,5)
  - [x] `models/execution_amendment.dart`: immutable `ExecutionAmendment` (amendmentId, unitId, unitNo,
        configuration?, leadId, description, status, createdAt, updatedAt) + `fromJson` (PII-free columns
        of `get_amendments_for_execution`). A pure `AmendmentStatus` helper: `label`, `isTerminal`, and
        `nextStatuses` (the allowed transitions) — matching the RPC's lifecycle. Flutter-free.
  - [x] `amendments_repository.dart`: `AmendmentsRepository(SupabaseClient)` with `logAmendment({unitId,
        leadId, description})` → `.rpc('log_amendment', …)`; `getAmendmentsForExecution({status})` →
        `.rpc('get_amendments_for_execution', …)`; `setAmendmentStatus({amendmentId, newStatus})` →
        `.rpc('set_amendment_status', …)`; `joinExecutionTeam(userId)` → `.rpc('add_execution_member', …)`.
        Typed `LogAmendmentException` (forbidden/notAmendable/notVisible/notLinked/notFound/descRequired)
        + `ExecutionException` (notMember/invalidTransition/notFound) each with a `friendly` getter.
        Co-located `@riverpod amendmentsRepository`.
- [x] **Task 2 — Providers** (`features/amendments/providers/`) (AC: 3) — `amendmentsForExecution(status?)`
      family; invalidate after a status change / join so the surface refetches through the RPC.
      `dart run build_runner build --delete-conflicting-outputs`.
- [x] **Task 3 — UI** (`features/amendments/ui/`) (AC: 1,2,3,4,5)
  - [x] `log_amendment_sheet.dart`: description field + Log button → `logAmendment`; friendly errors inline.
        Reached from the booking-dashboard hold card (has unit_id + lead_id + unit_no).
  - [x] `amendments_execution_screen.dart`: AppBar "Amendments"; a status filter row; the list (unit_no ·
        configuration · description + a status pill + per-row "Advance/Reject" actions from
        `nextStatuses`); loading/error/empty; pull-to-refresh (guarded). `not_execution_member` →
        a calm state + (for head) a "Join execution team" button (`add_execution_member(self)`).
- [x] **Task 4 — Wiring** (AC: 1,6) — a "Log amendment" action on the booking-dashboard hold card; a
      WORKSPACE "Amendments" row (`role == 'admin'`) → `/amendments`; the route.
- [x] **Task 5 — Tests** (`test/features/amendments/`) (AC: 1,2,3,4): `ExecutionAmendment.fromJson` +
      `AmendmentStatus` transitions/terminal; both exception mappings; a widget test of the execution
      screen (rows render PII-free + a status control; not-member calm state). analyze 0; suite green.
- [x] **Task 6 — Verify guards live on local Docker** (AC: 1,2,3,4,5) — seed an execution member + a
      logged amendment (`supabase/demo-amendments.local.sql`, LOCAL-ONLY, gitignored). Simulated-JWT:
      member log→amendment + lead timeline `amendment_logged`; partner→forbidden_role; member advances
      requested→acknowledged; non-member→not_execution_member; head join→member.

## Dev Notes

### The backend contract (already shipped — do NOT modify)
- `log_amendment(p_unit_id, p_lead_id, p_description) RETURNS uuid` — SECURITY DEFINER; guards non-partner
  tier, unit in-tenant + `hold|sold`, lead in-tenant + visible (`visible_user_ids()`), **and (0084) the
  lead must actually hold (active) or own (converted) the unit** (`lead_not_linked_to_unit`); dual-logs
  amendment_events + lead Timeline (`amendment_logged`). [0081 + 0084]
- `get_amendments_for_execution(p_status DEFAULT NULL)` — member-gated; returns unit_no/configuration/
  description/status + ids only, **no lead PII**. [0082]
- `set_amendment_status(p_amendment_id, p_new_status)` — member-gated; validates the lifecycle transition;
  appends `status_changed`. [0082]
- `add_execution_member(p_user_id)` — builder_head only. [0082]
[Source: 0080/0081/0082/0083/0084; 16-1..16-4 records]

### Entry point for logging (why the booking dashboard hold card)
`log_amendment` needs both a unit_id and its linked lead_id, and the 0084 link check requires the lead to
actually hold/own that unit. The booking-dashboard hold card already carries `unit_id` + `lead_id` for an
active hold — the cleanest in-scope entry. A rep-facing entry from the inventory unit-detail sheet is
deferred: `get_project_units` does not return the holding lead, so the sheet lacks a lead_id
(deferred-work.md).

### Execution entry gate (membership is not a JWT claim)
`tenant_execution_team` membership can't be read from the JWT, so the WORKSPACE entry is gated to
`role == 'admin'` (head) — cosmetic. Any user who opens the screen and isn't a member gets a calm
`not_execution_member` state; a head can self-join via `add_execution_member`. Broadening the entry to
non-head members needs a membership flag in the JWT or a client membership read (deferred-work.md).

### Structure / conventions (match Slices 1–3)
`features/amendments/{data/{models/},providers/,ui/}`; repo behind a co-located `@riverpod` provider;
immutable models + `fromJson`; typed exceptions from `PostgrestException`; top-level `GoRoute`; codegen
providers; `AppColors`; guarded RefreshIndicator refetch. Status pill mirrors the lead status-pill idiom.

### Local test env (FREE — never prod)
Docker Supabase up; `supabase/demo-amendments.local.sql` (LOCAL-only, gitignored) adds the head to
`tenant_execution_team` + logs one amendment against the seeded hold (from demo-booking-holds.local.sql).
Users: head (`c1000000-…0001`, role=admin), rep1 (`…00e1`), partner (`…0002`). Simulated-JWT (set local
role + request.jwt.claims, rollback).

### References
- [Source: epics.md#Story 16.2/16.3/16.4; architecture-builder-ops-v2.md §6, §13.1]
- [Source: 0081/0082/0084; 16-2/16-3/16-4 records]
- [Source: features/{booking,inventory,team}/* Slice 1–3 patterns; lead timeline amendment_logged (13-4-mobile)]

## Dev Agent Record

### Agent Model Used
claude-opus-4-8 (Amelia / bmad-dev-story)

### Completion Notes List
- New additive domain `features/amendments/{data,providers,ui}`. Consumes the shipped `log_amendment`
  (0081/0084), `get_amendments_for_execution` + `set_amendment_status` + `add_execution_member` (0082).
  No backend touched.
- **Log (AC1/AC2):** the "Log amendment" action on the booking-dashboard hold card opens a description
  sheet → `log_amendment(unit_id, lead_id, description)` (the hold card carries both ids, and the active
  hold satisfies the 0084 lead↔unit link). All guard tokens map via `LogAmendmentException.friendly`
  (forbidden / notAmendable / notLinked / notVisible / notFound / descRequired) — no PostgREST dump.
- **Execution surface (AC3/AC4):** `AmendmentsExecutionScreen` lists `get_amendments_for_execution`
  (unit_no · configuration · description + status pill — **no lead PII**) with per-row lifecycle actions
  derived from a pure `AmendmentStatus.nextStatuses` (mirrors the RPC's validated transitions) →
  `set_amendment_status`. `invalid_transition` / `not_execution_member` map to calm messages.
- **Head self-join (AC5):** membership is a table, not a JWT claim, so a non-member sees a calm state; a
  head gets a "Join execution team" button → `add_execution_member(self.uid)`.
- **Entry gates (AC6):** "Log amendment" rides the head/leader booking dashboard; the "Amendments" You-tab
  row is gated to `role == 'admin'` (cosmetic — the RPCs re-check membership/tier).
- **16.4 notify:** the in-app destinations exist (the execution surface + the lead Timeline
  `amendment_logged` label added in 13-4-mobile). The actual FCM push (edge fn `send-amendment-
  notification`, 0083) is dormant/undeployed — push + deep-link handling is out of this slice
  (deferred-work.md).
- **Verified live on local Docker (2026-07-11)** via `supabase/demo-amendments.local.sql` (LOCAL-only) +
  simulated-JWT SQL (mutations rolled back): head `log_amendment` on the held unit → created; head
  (member) `get_amendments_for_execution` → 1 PII-free row; `set_amendment_status` requested→acknowledged
  → ok; partner `log_amendment` → **forbidden_role**; rep (non-member) execution read →
  **not_execution_member**; requested→done → **invalid_transition**. On-device look-pass for Rudra.

### File List
**New**
- apps/mobile/lib/features/amendments/data/models/execution_amendment.dart
- apps/mobile/lib/features/amendments/data/amendments_repository.dart
- apps/mobile/lib/features/amendments/data/amendments_repository.g.dart (generated)
- apps/mobile/lib/features/amendments/providers/amendments_providers.dart
- apps/mobile/lib/features/amendments/providers/amendments_providers.g.dart (generated)
- apps/mobile/lib/features/amendments/ui/log_amendment_sheet.dart
- apps/mobile/lib/features/amendments/ui/amendments_execution_screen.dart
- apps/mobile/test/features/amendments/execution_amendment_test.dart
- apps/mobile/test/features/amendments/amendments_exception_test.dart
- apps/mobile/test/features/amendments/amendments_execution_screen_test.dart
- nirman-crm/supabase/demo-amendments.local.sql (LOCAL-only seed, gitignored)

**Modified**
- apps/mobile/lib/features/booking/ui/booking_dashboard_screen.dart (Log amendment action on hold card)
- apps/mobile/lib/router/app_router.dart (/amendments route)
- apps/mobile/lib/features/home/ui/you_screen.dart (Amendments entry row, head-gated)

## Review Findings

_Code review 2026-07-11 (3 lenses inline). **0 confirmed correctness findings, 2 low no-fix / deferred.**
ACs 1–6 satisfied; RPC-authoritative log + execution lifecycle, PII minimization, calm errors, and the
head self-join verified. Suite 243/243, analyze 0 errors._

- [ ] [Review][Low][Deferred] Logging entry is only on the booking dashboard (head/leader). A
  `front_line_rep` who holds a unit has no in-app entry to log an amendment, because the inventory
  unit-detail read (`get_project_units`) doesn't return the holding lead. Rep-facing entry deferred —
  deferred-work.md.
- [ ] [Review][Low][Deferred] 16.4 FCM push + deep-link into an amendment is not wired (the edge fn is
  dormant/undeployed). In-app destinations (execution surface + lead Timeline) exist; push handling is a
  follow-up — deferred-work.md.

## Change Log
- 2026-07-11: Story drafted (bmad-create-story) — mobile amendments (log + execution surface) slice of 16.2/16.3.
- 2026-07-11: Implemented `features/amendments` — log-amendment sheet (from booking hold card) +
  execution-team surface (PII-free list + lifecycle via set_amendment_status + head self-join). 18 new
  tests; analyze 0; full suite 243/243. Guards + lifecycle verified live on local Docker (simulated JWT +
  local seed). Status → review.
- 2026-07-11: Code review (3 lenses inline) — 0 confirmed findings; 2 low deferred (rep log entry, 16.4
  push deep-link). Status → done.
