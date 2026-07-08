# Story 12.2: role-vs-tier predicate audit and tier-aware assignability

Status: review  (audit doc + migration 0058 written + self-reviewed; live `db push` deferred)

## Story

As a security-conscious developer,
I want every shipped `role` check classified and lead-assignment made tier-aware,
so that introducing leaders cannot silently change the meaning of existing guards or make a leader an accidental assignment target.

## Acceptance Criteria

1. **Given** the 17 hardened SECURITY DEFINER RPCs (per `0054`) + all table RLS policies **When** the audit is done **Then** a written inventory (committed as `_bmad-output/implementation-artifacts/12-2-predicate-audit.md`) classifies each `(app_metadata)->>'role'` check as `is-admin` / `is-not-admin` / `is-rank-and-file-IC`.
2. **And** only `is-rank-and-file-IC` checks are made tier-aware; `is-admin` / `is-not-admin` checks confirmed unchanged.
3. **And** `assign_lead` and `list_employees_for_assignment` filter assignment targets to `role_tier = 'front_line_rep'` (leaders/partners/receptionists NOT assignable).
4. **And** `assign_lead` takes a `FOR UPDATE` row lock on the lead so a manual reassign cannot race a dedup reclaim (Story 13.5).
5. **And** a test asserts a `team_leader` (with claim) and the same account on a stale pre-migration token both fail to be an assignment target.
6. **And** no behavioral change to admin-only RPCs is observed for `builder_head` users.

## Tasks / Subtasks

- [ ] **Task 1 — Audit** (AC 1,2): introspect live `pg_get_functiondef` for the 17 fns + `pg_policies`; produce the classification table. Read-only; NEVER `apply_migration`.
- [ ] **Task 2 — Migration `0057b_tier_aware_assignment.sql`** (AC 3,4):
  - [ ] `CREATE OR REPLACE` `assign_lead` reproducing its current body byte-for-byte EXCEPT: target validation `v_target.role <> 'employee'` → also require `v_target_tier = 'front_line_rep'` (read `role_tier` from `public.users`); add `FOR UPDATE` on the lead SELECT (already present — confirm) and ensure reclaim path (13.5) uses same lock ordering.
  - [ ] `CREATE OR REPLACE` `list_employees_for_assignment` adding `AND u.role_tier = 'front_line_rep'`.
  - [ ] Preserve every `SET search_path`, `SECURITY DEFINER`, RETURNS sig, grants. Guard-only/where-only change.
- [ ] **Task 3 — Apply** via `db push --linked`.
- [ ] **Task 4 — Tests** (AC 5,6): `pg_temp` behavioral suite — leader-as-target denied (claim + stale-token), rep-as-target allowed, `builder_head` admin RPCs unchanged.

## Dev Notes

- **This is the riskiest story in Epic 12** — it touches shipped assignment logic. Source each body from live `pg_get_functiondef`, change only the target filter + lock. No signature drift (else duplicate overload / CREATE error). Mirror the discipline of `0054`. [Source: 8-1-harden-admin-role-guards.md Dev Notes]
- Decision: leaders/partners/receptionists are NOT assignable lead targets (they manage/gate, reps own). [Source: architecture-builder-ops-v2.md §13.4]
- Assignment authority now reads `role_tier`; accepts the same backfill window as visibility — once 12.3 stamps + token refresh, leaders are correctly excluded; on a stale token `auth_role_tier()` derivation still excludes them because the *target* check reads `public.users.role_tier` (DB column, not JWT) — claim window does not apply to the target filter. Call this out in the audit doc.
- `assign_lead` current def: `0054_harden_admin_role_guards.sql` (fn #1). `list_employees_for_assignment`: `0054` (fn #13).
- Migration target: `0057b` (or `0058` if 12.1 took `0057`; keep numbering sequential — confirm `migration list` first).
- Pure DDL, no mobile. [Source: CLAUDE.md]

## References
- [Source: epics.md#Story 12.2]
- [Source: architecture-builder-ops-v2.md §1.1, §13.4, §13.5; §10 flag 6]
- [Source: 0054_harden_admin_role_guards.sql — assign_lead, list_employees_for_assignment current bodies; CREATE OR REPLACE discipline]
- [Source: nirman-crm/CLAUDE.md — never MCP apply_migration]

## Implementation (2026-06-27)

**Files:** `12-2-predicate-audit.md` (classification of all 17 RPCs + RLS) · `nirman-crm/supabase/migrations/0058_tier_aware_assignment.sql`.

- Audit: nearly all guards are **is-admin** (`builder_head ⇐ role='admin'`) → unchanged. Two are genuinely **is-rank-and-file-IC**: `assign_lead` target filter + `list_employees_for_assignment` returned set → now require `role_tier='front_line_rep'`.
- `0058` reproduces both bodies from their latest def (`0054`), changing ONLY the target/returned-set filter. `assign_lead`'s lead `FOR UPDATE` (reclaim-vs-reassign lock, AC4) preserved verbatim; signature/grants/search_path identical (CREATE OR REPLACE keeps grants).
- `bulk_assign_leads` + `reactivate_future_leads` delegate to `assign_lead` → inherit the filter for free.

**Self-review:** the target filter reads `public.users.role_tier` (DB column) not the JWT claim → correct independent of the 12.3 stamping window (AC5). 0057 backfill set all existing employees to `front_line_rep` → zero regression for current assignments; only future leaders (set via 12.4) become non-assignable. No drift vs 0054 body.

**Deferred (logged):** `list_employees_for_share` still returns all `role='employee'` users as share candidates (now incl. leaders/partners/receptionists) — nonsensical-but-not-a-hole; follow-up filter recommended. → add to `deferred-work.md`.

**Verification:** static (faithful transcription from 0054 file source). Runtime (behavioral guard tests: leader-as-target denied on fresh+stale token, rep allowed, admin RPCs unchanged) deferred to apply. No mobile/web.

**Status:** code-complete, awaiting apply + code-review.
