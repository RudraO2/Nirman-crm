---
baseline_commit: 596238c1176640da3f0b37b089fb220fab4ad2ac
---
# Story 13.4-mobile: reception verifies a visit by customer code (Flutter UI)

Status: review

<!-- Mobile-UI completion of Story 13.4. The backend (migration 0067 verify_visit + the
customer_code/visit_count columns from 0062/0065 + the visit_verified/visit_logged/code_generated
timeline enum values) is DONE on prod and recorded in 13-4-reception-verify-visit.md +
13-3-customer-code-gen-whatsapp-delivery.md — do NOT touch it. This story is ONLY the deferred mobile
surface: the reception check-in screen (code → verify_visit) plus surfacing customer_code + the visit
ordinal on lead detail. Named `13-4-mobile-*` to preserve the backend story record. Slice 3 of the
mobile builder-ops build (Slice 1 = features/inventory, Slice 2 = features/hierarchy + team).

Note: the create-path lead-registration v2 mobile UI (13.2 secondary phone + budget/config, 13.3
customer-code result dialog + wa.me delivery) is ALREADY built in features/leads/ui/new_lead_sheet.dart.
This story does NOT rebuild it. -->

## Story

As a Receptionist,
I want to enter a customer's visit code to record their walk-in,
so that the visit is logged against the right lead and the visit count increments — without me needing
access to the lead's private details.

## Acceptance Criteria

1. **Given** a `receptionist` (or `builder_head`) on the reception check-in screen **When** I enter a
   customer code and tap Verify **Then** the client calls `verify_visit(p_code)` and, on success, shows a
   calm confirmation carrying the new visit ordinal ("Visit #2 recorded") — the RPC is authoritative;
   the client never mutates `leads`/`lead_timeline` directly.
2. **And** an invalid / unknown / wrong-tenant code maps the RPC's `invalid_customer_code` to a calm
   inline message ("No lead matches that code — check and re-enter"), not a red PostgREST dump; the input
   stays so the receptionist can correct it.
3. **And** a caller whose tier cannot verify (`permission_denied` / `not_authenticated`) sees a calm
   "You don't have access to reception check-in" message (server backstop; the entry is also role-gated
   client-side, so this is only reachable via a leaked/edge route).
4. **And** the code input is normalised to uppercase and trimmed on the client (mirrors the RPC's
   `upper(trim(code))`), so `nir-44d77` and `NIR-44D77` both resolve.
5. **And** on the lead detail screen the lead's `customer_code` is shown (for the agent to read out) and,
   when `visit_count > 0`, the current visit ordinal ("2nd visit") — read via a lightweight tenant-scoped
   direct select (`leads.select('customer_code, visit_count')`), since the frozen `get_lead_by_id` RPC
   does not return these columns and this slice must not change the backend.
6. **And** the lead Timeline renders the new event types with friendly labels: `code_generated`
   ("Visit code generated"), `visit_verified` ("Visit verified"), `visit_logged` ("Visit logged"),
   plus `amendment_logged` ("Amendment logged") ahead of Story 16-2-mobile.
7. **And** the reception surface exposes NO lead PII — the verify result shows only the ordinal + the
   entered code (receptionist stays gate-not-own per 12.6; `verify_visit` returns lead_id + visit_count,
   never the name/phone).

## Tasks / Subtasks

- [x] **Task 1 — Reception data layer** (`features/reception/data/`) (AC: 1,2,3,4,7)
  - [x] `models/visit_result.dart`: immutable `VisitResult(leadId, visitCount)` + `fromJson` (keys
        `lead_id`, `visit_count`, matching the RPC's `jsonb_build_object`). Flutter-free.
  - [x] `reception_repository.dart`: `ReceptionRepository(SupabaseClient)` with
        `Future<VisitResult> verifyVisit(String code)` → `.rpc('verify_visit', {'p_code': code})`.
        Typed `VerifyVisitException.fromPostgrest` mapping `invalid_customer_code` (→ notFound),
        `permission_denied`/`not_authenticated` (→ notAllowed), else the raw message, each with a
        `friendly` getter. Expose `@riverpod ReceptionRepository receptionRepository(...)` (repo
        provider co-located, matching `inventory_repository.dart`/`team_repository.dart`).
- [x] **Task 2 — Reception UI** (`features/reception/ui/`) (AC: 1,2,3,4,7)
  - [x] `verify_visit_screen.dart`: AppBar "Reception check-in"; a single uppercase-forced autofocus
        code field + a "Verify visit" button (disabled while empty/submitting); on success a green result
        card ("Visit #N recorded · <code>") + the field clears for the next walk-in; on
        `VerifyVisitException` shows the `friendly` message inline. Colours via `AppColors` only.
- [x] **Task 3 — Lead-detail surfacing** (`features/leads`) (AC: 5,6)
  - [x] `LeadRepository.getLeadCodeVisit(leadId)` → tenant-scoped `leads.select('customer_code,
        visit_count').eq('id', leadId).maybeSingle()` → `LeadCodeVisit(customerCode?, visitCount)`;
        `@riverpod leadCodeVisit(id)` provider. Fail-soft (null on error) — never blocks the detail view.
  - [x] `lead_detail_screen.dart`: add a "Visit code" detail row (copyable) + a "Visits" row showing the
        ordinal when `visit_count > 0`. Add the four new timeline labels to `_eventDisplay` +
        `visit_verified`/`visit_logged` detail (`visit_ordinal`).
- [x] **Task 4 — Wiring** (AC: 1)
  - [x] `router/app_router.dart`: top-level `GoRoute('/reception/verify')` → `VerifyVisitScreen`.
  - [x] `you_screen.dart`: a WORKSPACE "Reception check-in" row shown when
        `roleTier == 'receptionist' || role == 'admin'` (best-effort cosmetic gate; `verify_visit`
        re-checks tier server-side).
- [x] **Task 5 — Tests** (`test/features/reception/`, `test/features/leads/`) (AC: 1,2,3,4,5,6)
  - [x] `VisitResult.fromJson`; `VerifyVisitException.fromPostgrest`/`friendly` for each token; the
        uppercase-normalisation helper; a widget test of the verify screen (success clears + shows
        ordinal, error keeps input + shows friendly message) with a fake repo; the ordinal formatter
        (1st/2nd/3rd/Nth); the new timeline labels.
  - [x] `flutter analyze` 0 errors; full suite green.
- [x] **Task 6 — Verify guards live on local Docker** (AC: 1,2,3,7) — simulated-JWT SQL against the demo
      seed (all rolled back): reception verifies `NIR-44D77` → visit_count 0→1 + 2 timeline events;
      front_line_rep caller → `permission_denied`; unknown code → `invalid_customer_code`.

## Dev Notes

### The backend contract (already shipped — do NOT modify)
`verify_visit(p_code text) RETURNS jsonb` — SECURITY DEFINER, `authenticated` only, guards
`auth_role_tier() IN ('receptionist','builder_head')` (else `permission_denied` 42501), tenant via
`auth_tenant_id()`, resolves `upper(trim(p_code))` → lead `FOR UPDATE`, `visit_count++` + `last_action_at`,
logs `visit_verified` + `visit_logged` with `visit_ordinal = new count`; unknown/empty/wrong-tenant →
`invalid_customer_code` (P0002). Returns `{lead_id, visit_count}`.
[Source: nirman-crm/supabase/migrations/0067_verify_visit.sql]

### Why lead-detail surfacing uses a direct read (not the RPC)
`get_lead_by_id` / `get_my_leads` return neither `customer_code` nor `visit_count` (verified live via
`pg_get_function_result`). The backend is frozen this slice, so the detail screen reads the two columns
directly: `leads` has `GRANT SELECT ... TO authenticated` under the `leads_tenant_isolation` RLS policy
(`tenant_id = auth_tenant_id()`), so a single-row tenant-scoped select is safe and cheap. **List-card**
surfacing of the code/ordinal across `get_my_leads` rows is intentionally NOT done — that would require a
`get_my_leads` column addition (a backend migration), out of scope here. Recorded in deferred-work.md.
[Source: 0009_create_leads.sql RLS/grants; live pg_get_function_result]

### Receptionist PII discipline (12.6)
The receptionist is gate-not-own: denied `get_my_leads` / lead-edit RPCs. `verify_visit` is the one
mutation they may call, and it returns only `lead_id`+`visit_count` — no decrypt. The reception screen
therefore shows only the ordinal + the code the receptionist typed. Do NOT add a lead lookup there.
[Source: 12-6 story; 0067 self-review]

### Structure / conventions (match Slices 1–2)
`features/reception/{data/{models/},ui/}`; repo = plain class taking `SupabaseClient` behind a
co-located `@riverpod` provider; models immutable + `fromJson`; typed exception from `PostgrestException`
(mirror `TeamAccessException`/`InventoryAccessException`). Routes are top-level `GoRoute`s. Providers use
codegen → `dart run build_runner build --delete-conflicting-outputs`. Colours via `AppColors`.
[Source: features/inventory/*, features/team/*; app_router.dart; you_screen.dart]

### Local test env (FREE — never prod)
Docker Supabase up; demo seed `supabase/demo-builder-ops.local.sql`. Demo tenant Nirman Media leads
already carry codes (e.g. `NIR-44D77`, visit_count 0) so verify is testable with no extra seed. Users:
`reception@nirman.local` (receptionist, uid `c1000000-…0003`), `head@nirman.local` (builder_head),
`rep1@nirman` (front_line_rep, uid `…00e1`). Simulated-JWT pattern (set local role + request.jwt.claims,
rollback) as in the 12-x-mobile records.

### References
- [Source: epics.md#Story 13.4; architecture-builder-ops-v2.md §5.1 FR-44/46, §13.1 receptionist]
- [Source: nirman-crm/supabase/migrations/0067_verify_visit.sql; 0062/0065 columns + timeline enum]
- [Source: 13-4-reception-verify-visit.md, 13-3-customer-code-gen-whatsapp-delivery.md (backend records)]
- [Source: nirman-crm/apps/mobile/lib/features/{inventory,team,leads}/* (Slice 1–2 patterns)]

## Dev Agent Record

### Agent Model Used
claude-opus-4-8 (Amelia / bmad-dev-story)

### Completion Notes List
- New additive domain `features/reception/{data,ui}` mirroring Slices 1–2. Consumes the shipped
  `verify_visit` RPC (0067) only; no backend touched.
- **RPC-authoritative (AC1):** the screen sends the trimmed/uppercased code and renders the returned
  ordinal; it never mutates `leads`/`lead_timeline`. Rejections map via `VerifyVisitException.friendly`
  to calm sentences (AC2/AC3) — no PostgREST dump; the input is retained on `invalid_customer_code`.
- **Uppercase normalisation (AC4):** both a client `_UpperCaseFormatter` (live) and
  `ReceptionRepository.normalizeCode` (before the call) mirror the RPC's `upper(trim())`.
- **PII discipline (AC7):** the verify result shows only `<code> · Nth visit` (ordinal from the RPC's
  `visit_count`) — no lead name/phone; the receptionist stays gate-not-own.
- **Lead-detail surfacing (AC5):** `get_lead_by_id` returns neither `customer_code` nor `visit_count`
  (verified live via `pg_get_function_result`), and the backend is frozen, so a lightweight
  `leadCodeVisit` provider direct-reads the two columns from `leads` under the tenant-isolation RLS
  (single-row, fail-soft null). Shown as "Visit code" + "Visits" detail rows. **Card-list** surfacing
  across `get_my_leads` is intentionally deferred (would need a `get_my_leads` column addition =
  backend migration) — recorded in deferred-work.md.
- **Timeline labels (AC6):** added `code_generated`/`visit_verified`/`visit_logged`/`lead_reclaimed`/
  `amendment_logged` to `_eventDisplay`, plus `visit_ordinal`/`description` detail rendering.
- **Entry gate:** WORKSPACE "Reception check-in" row shows when `roleTier == 'receptionist' || role ==
  'admin'` (cosmetic; `verify_visit` re-checks the tier server-side → a leaked screen verifies nothing).
- **Verified live on local Docker (2026-07-11)** via simulated-JWT SQL against the demo seed
  (mutating case rolled back): reception verifies `nir-44d77` (lowercase → normalised) → visit_count
  0→1 + `visit_verified` & `visit_logged` both ordinal 1; front_line_rep caller → `permission_denied`;
  unknown code → `invalid_customer_code`. On-device visual look-pass still for Rudra (same posture as
  Slices 1–2).

### File List
**New**
- apps/mobile/lib/features/reception/data/models/visit_result.dart
- apps/mobile/lib/features/reception/data/reception_repository.dart
- apps/mobile/lib/features/reception/data/reception_repository.g.dart (generated)
- apps/mobile/lib/features/reception/ui/verify_visit_screen.dart
- apps/mobile/test/features/reception/visit_result_test.dart
- apps/mobile/test/features/reception/reception_repository_test.dart
- apps/mobile/test/features/reception/verify_visit_screen_test.dart

**Modified**
- apps/mobile/lib/features/leads/data/models/lead_model.dart (LeadCodeVisit)
- apps/mobile/lib/features/leads/data/lead_repository.dart (getLeadCodeVisit)
- apps/mobile/lib/features/leads/providers/lead_providers.dart (+ leadCodeVisit provider)
- apps/mobile/lib/features/leads/providers/lead_providers.g.dart (generated)
- apps/mobile/lib/features/leads/ui/lead_detail_screen.dart (code/visit rows + timeline labels)
- apps/mobile/lib/router/app_router.dart (/reception/verify route)
- apps/mobile/lib/features/home/ui/you_screen.dart (Reception check-in entry row)

## Review Findings

_Code review 2026-07-11 (3 lenses inline: Blind Hunter / Edge-Case Hunter / Acceptance Auditor).
**0 confirmed correctness findings, 1 UX polish applied, 1 low no-fix.** ACs 1–7 satisfied; RPC-
authoritative wiring + error mapping + PII discipline + the direct-read surfacing verified. Suite
214/214, analyze 0 errors._

- [x] [Review][Polish] Verify screen kept a prior success card visible above a fresh error on the next
  attempt — cleared `_lastResult` at the start of `_verify` so the result panel never shows stale
  success next to a new error message. No behaviour change on the happy path.
- [ ] [Review][Low][No-fix] `getLeadCodeVisit` is fail-soft (null on any error), so a transient read
  failure is indistinguishable from a lead that has no code yet — both hide the rows. Acceptable: the
  detail view must never be blocked by a supplementary read, and the code is also shown at creation
  time (13.3 dialog) and on the reception result. Noted for honesty.

## Change Log
- 2026-07-11: Story drafted (bmad-create-story) — mobile reception verify-visit + lead-detail
  code/ordinal surfacing slice of 13.4.
- 2026-07-11: Implemented `features/reception` (verify screen → verify_visit) + lead-detail
  code/visit surfacing (direct tenant-scoped read) + 4 new timeline labels + route + entry row.
  10 new tests; analyze 0 errors; full suite 214/214. Guards + happy path verified live on local
  Docker (simulated JWT). Status → review.
- 2026-07-11: Code review (3 lenses inline) — 0 confirmed correctness findings; 1 UX polish applied
  (stale success card), 1 low no-fix. Status → done.
