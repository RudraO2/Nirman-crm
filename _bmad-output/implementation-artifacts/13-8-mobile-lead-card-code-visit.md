---
baseline_commit: 596238c1176640da3f0b37b089fb220fab4ad2ac
---
# Story 13.8-mobile: lead-card customer_code + visit ordinal (Flutter UI + read RPCs)

Status: done

<!-- Closes the Slice-3 leftover recorded in deferred-work.md ("13.4-mobile — lead-card
customer_code + visit ordinal"). Slice 3 surfaced customer_code + the visit ordinal on lead DETAIL
only, via a lightweight tenant-scoped DIRECT read shim (get_lead_by_id / get_my_leads did not return
the columns). This story surfaces them on the lead LIST CARD too, PROPERLY through the read RPCs, and
retires the shim. Named 13-8-mobile-* to PRESERVE the existing 13-x backend story records at their keys
(13-4-reception-verify-visit, 13-4-mobile-reception-verify-visit, etc.). -->

## Story

As a builder-side agent,
I want a lead's visit code and walk-in count on the lead LIST card (not only the detail screen),
so that I can read out a customer's code and see how many times they've visited at a glance.

## Acceptance Criteria

1. **Given** the read RPCs `get_my_leads` and `get_lead_by_id` **When** they return a lead row **Then**
   each row now also carries `customer_code` (nullable text) and `visit_count` (int, 0 default) — added to
   the RETURNS TABLE + SELECT of BOTH functions via ONE new file-based migration (0093), each reproduced
   VERBATIM from its latest prod definition with ONLY the two columns appended.
2. **And** `get_my_leads` keeps its 0092 tenant chokepoint guard UNCHANGED — a suspended/cancelled tenant
   still raises `missing_tenant_context` (P0001) and returns NO data (guard is NOT weakened), plus the 12.6
   receptionist deny stays.
3. **And** the mobile `LeadListItem` + `LeadDetail` parse `customerCode` + `visitCount` from the RPC row
   (`fromJson`), defaulting to `null` / `0` when absent.
4. **And** the `LeadCard` renders the customer code (when present) and, when `visit_count > 0`, the visit
   ordinal ("2nd visit") — using the shared `visitOrdinal` helper (extracted from lead_detail_screen so the
   ordinal logic lives in one place).
5. **And** the direct-read shim is RETIRED: `LeadRepository.getLeadCodeVisit`, the `leadCodeVisit`
   provider, the `LeadCodeVisit` model, and their use in `lead_detail_screen` are removed; the detail screen
   reads `customer_code` / `visit_count` off the `get_lead_by_id` RPC row instead.
6. **And** the migration is applied LOCALLY only (Docker); the prod `db push --linked` is left as an
   explicit pending step for Rudra.

## Tasks / Subtasks

- [x] **Task 1 — Backend migration 0093** (AC: 1,2) — `0093_lead_reads_customer_code_visit_count.sql`.
  - [x] `DROP FUNCTION` + `CREATE` `get_my_leads(int,int)` = 0092 body verbatim (guard + receptionist deny
        + PII + UNION ALL + scored + final SELECT) with `customer_code text, visit_count int` appended to
        the RETURNS TABLE, both UNION branches (`l.customer_code, l.visit_count`), the `scored` CTE, and the
        final SELECT. (CREATE OR REPLACE cannot change the OUT-param row type → DROP first, no CASCADE.)
  - [x] Same for `get_lead_by_id(uuid)` = 0044 body verbatim + the two columns appended.
  - [x] Re-issue `REVOKE ... FROM PUBLIC, anon` + `GRANT ... TO authenticated` on both.
- [x] **Task 2 — Mobile model** (AC: 3) — `lead_model.dart`: `customerCode` + `visitCount` on
      `LeadListItem` (+ ctor + `fromJson`, default null/0); `LeadDetail` super passthrough + copy in its
      `fromJson`. Add top-level `visitOrdinal(int)` helper; delete the `LeadCodeVisit` model.
- [x] **Task 3 — Retire the shim** (AC: 5) — remove `LeadRepository.getLeadCodeVisit`, the `leadCodeVisit`
      `@riverpod` provider; regenerate codegen.
- [x] **Task 4 — Lead detail** (AC: 5) — read `lead.customerCode` / `lead.visitCount` off the RPC row;
      `_visitLabel` + the timeline `visit_ordinal` detail both call shared `visitOrdinal`; delete the two
      duplicate local ordinal helpers.
- [x] **Task 5 — Lead card** (AC: 4) — code + ordinal line under the phone·location meta line, dim-aware
      (`metaColor`), ellipsis-guarded, only shown when code or visits present.
- [x] **Task 6 — Tests** (AC: 3,4) — `lead_model_test`: fromJson parses/defaults the two fields;
      `LeadDetail` passthrough; `visitOrdinal` (1st/2nd/3rd/teens/last-digit/0). `lead_card_test`: card
      shows code, shows ordinal when count>0, hides when 0 / absent. `flutter analyze` 0 errors; full suite.
- [x] **Task 7 — Verify guards live on local Docker** (AC: 1,2) — apply 0093 via psql to local; sim-JWT SQL
      (rolled back): active rep1 `get_my_leads` returns customer_code + visit_count; `get_lead_by_id` too;
      SUSPENDED tenant `get_my_leads` still raises `missing_tenant_context` (P0001).

## Dev Notes

### Why this needs a migration (vs the 13.4-mobile shim)
`get_my_leads` / `get_lead_by_id` did not return `customer_code` / `visit_count`, so 13.4-mobile surfaced
them on lead detail via a per-lead direct `leads.select('customer_code, visit_count')`. That is fine for a
single detail view but wasteful per-row across a whole list card. The proper fix — recorded as deferred —
is to add the columns to the read RPCs. `leads.customer_code` is nullable text; `leads.visit_count` is
`int NOT NULL DEFAULT 0` (migration 0062). Column types match the appended RETURNS TABLE declarations.
[Source: deferred-work.md "13.4-mobile — lead-card customer_code + visit ordinal"; 0062_lead_deltas.sql]

### Preserving the 0092 guard
`get_my_leads` was hardened in 0092 (Story 9.6) with the tenant chokepoint (`auth_tenant_id() IS NULL ->
missing_tenant_context P0001`) + the 12.6 receptionist deny. 0093 reproduces that body EXACTLY and only
appends columns — the guard is not weakened. Verified live (suspended tenant still raises P0001).
[Source: 0092_hard_tenant_cutoff.sql]

### Migration numbering + prod push
Prod head is 0092 → this is file 0093. Applied to LOCAL Docker only this story (via psql; local
schema_migrations table tops at 0088 but the live function bodies already carry 0089–0092 from prior
direct application, so `db push` was avoided in favour of the idempotent CREATE). **Prod `supabase db push
--linked` is PENDING — an explicit step for Rudra.** NEVER MCP apply_migration.
[Source: nirman-crm/CLAUDE.md §Supabase]

### Local test env
Docker Supabase up; demo seed `supabase/demo-builder-ops.local.sql`. Tenant Nirman Media
(`00000000-…-0001`); `rep1@nirman` (uid `…00e1`) owns leads `NIR-44D77` / `NIR-6CD66`. Sim-JWT pattern
(set local role authenticated + request.jwt.claims, rollback), per the 12-x / 13-4-mobile records.

### References
- [Source: deferred-work.md; 13-4-mobile-reception-verify-visit.md (the shim being retired)]
- [Source: nirman-crm/supabase/migrations/0092_hard_tenant_cutoff.sql, 0044_review_patches_4_4.sql]
- [Source: nirman-crm/apps/mobile/lib/features/leads/* (Slice 1–3 patterns)]

## Dev Agent Record

### Agent Model Used
claude-opus-4-8 (Amelia / bmad-dev-story)

### Completion Notes List
- **One migration (0093)**, both read RPCs, `DROP`+`CREATE` (return-type change) with the exact prior
  bodies + two appended columns; GRANTs re-issued. Guard preserved (verified P0001 live).
- **Shim fully retired:** `LeadCodeVisit` model, `getLeadCodeVisit` repo method, `leadCodeVisit` provider
  all removed; detail + card read the fields off the RPC row. No dangling references (grep-verified).
- **One ordinal helper:** extracted `visitOrdinal(int)` to `lead_model.dart`; the two duplicate local
  ordinal fns in `lead_detail_screen` (`_ordinal`, `_TimelineRow._ord`) deleted and re-pointed at it.
- **Card surface:** code + "Nth visit" on a dim-aware line under phone·location, shown only when present.
- **Verified live on local Docker (2026-07-11)** via sim-JWT (rolled back): active rep1 → `get_my_leads`
  returns `NIR-44D77` visit_count 2 + `NIR-6CD66` 0; `get_lead_by_id` returns code+count; SUSPENDED tenant
  → `missing_tenant_context` (P0001), no data. `flutter analyze` 0 errors; full suite **254/254** (+11).
- **Scope note (not a defect):** `get_my_archived_leads` was intentionally NOT changed, so archived-list
  cards do not show code/ordinal (active list + detail only, per the deferred item). Codegen re-run.
- **Prod migration push PENDING** (Rudra runs `db push --linked`); not committed (Slice-1–3 posture).

### File List
**New**
- nirman-crm/supabase/migrations/0093_lead_reads_customer_code_visit_count.sql

**Modified**
- nirman-crm/apps/mobile/lib/features/leads/data/models/lead_model.dart (customerCode/visitCount on
  LeadListItem+LeadDetail; visitOrdinal helper; LeadCodeVisit removed)
- nirman-crm/apps/mobile/lib/features/leads/data/lead_repository.dart (getLeadCodeVisit removed)
- nirman-crm/apps/mobile/lib/features/leads/providers/lead_providers.dart (leadCodeVisit provider removed)
- nirman-crm/apps/mobile/lib/features/leads/providers/lead_providers.g.dart (generated)
- nirman-crm/apps/mobile/lib/features/leads/ui/lead_detail_screen.dart (RPC-row read; shared ordinal)
- nirman-crm/apps/mobile/lib/features/leads/ui/lead_card.dart (code + ordinal line)
- nirman-crm/apps/mobile/test/features/leads/lead_model_test.dart (+7 tests)
- nirman-crm/apps/mobile/test/features/leads/lead_card_test.dart (+4 tests)

## Review Findings

_Code review 2026-07-11 (3 lenses inline: Blind Hunter / Edge-Case Hunter / Acceptance Auditor).
**0 confirmed correctness findings.** ACs 1–6 satisfied. Backend: guard reproduced verbatim + verified
live (P0001 on suspend); columns flow through both RPCs by name (order matches RETURNS TABLE); DROP has no
CASCADE (fail-loud on any dependency). Mobile: shim fully retired (grep-clean), ordinal logic single-
sourced, null/0-safe parse, card guards on presence. Suite 254/254, analyze 0 errors._

- [ ] [Review][Low][No-fix] `get_my_archived_leads` still omits the two columns → archived cards show no
  code/ordinal. By design (story scope = active list + detail); a one-line column add would extend it if
  ever wanted. Noted for honesty.

## Change Log
- 2026-07-11: Story drafted + implemented (bmad-create-story → bmad-dev-story) — migration 0093 (both read
  RPCs + columns), mobile model/card/detail surfacing, shim retired, shared visitOrdinal. 11 new tests;
  analyze 0 errors; suite 254/254. Guards + columns verified live on local Docker (sim-JWT). Status → done.
- 2026-07-11: Code review (3 lenses inline) — 0 confirmed correctness findings; 1 low no-fix (archived
  list scope). Status → done.
