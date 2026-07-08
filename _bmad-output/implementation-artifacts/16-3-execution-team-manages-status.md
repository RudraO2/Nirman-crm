# Story 16.3: execution team manages amendment status

Status: review  (migration 0082 written + applied + smoke ALL PASS 2026-06-28)

## Implementation (2026-06-28)

**File:** `nirman-crm/supabase/migrations/0082_amendment_status_mgmt.sql`

- `set_amendment_status(amendment, new_status)` — caller must be in `tenant_execution_team` (else `not_execution_member`); validates lifecycle (requested→acknowledged→in_progress→done, or →rejected from any non-terminal; else `invalid_transition`); UPDATE + append immutable `status_changed` event (via 0080 helper).
- `add_execution_member(user)` / `remove_execution_member(user)` — builder_head only; validates user in tenant.
- `get_amendments_for_execution(status?)` — member-gated surface returning unit_no/configuration/description/status **only — NO lead name/phone decryption** (AC4 PII minimization).

**Tested (local runtime):** head add member → size 1; member requested→acknowledged (+status_changed event); acknowledged→done (skip) → invalid_transition; valid chain ack→in_progress→done; non-member → not_execution_member; execution surface returns rows with no PII columns; non-head add_execution_member → permission_denied.

**Deferred:** admin/mobile execution surface UI (amendment list + status control).

## Story

As an execution-team member,
I want a surface to update an amendment's status,
so that the build/fit-out progress is tracked and the agent is kept informed.

## Acceptance Criteria

1. **Given** a user listed in `tenant_execution_team` **When** they open the amendments surface **Then** they see amendments for their tenant and can move status (requested→acknowledged→in_progress→done, or rejected).
2. **And** each status change appends an `amendment_status_changed` event (immutable trail).
3. **And** a user not in the execution team cannot change amendment status.
4. **And** the execution surface does not expose lead PII beyond what's needed to action the amendment.

## Tasks / Subtasks

- [ ] **Task 1 — `set_amendment_status(amendment_id, new_status)` RPC**: guard caller ∈ `tenant_execution_team` (tenant-scoped); validate transition; UPDATE amendment; append `amendment_status_changed`.
- [ ] **Task 2 — Head manages membership**: `add/remove_execution_member` (head-only) on `tenant_execution_team`.
- [ ] **Task 3 — Execution surface**: amendment list + status control (admin web and/or mobile). Minimal lead context (unit_no, configuration, description) — NO phone/name beyond need.
- [ ] **Task 4 — Tests**: member changes status + logs; non-member denied; PII minimization; head manages membership.

## Dev Notes

- Execution members are in-system users (any tier) flagged via membership — gives them the surface to close the loop. [Source: architecture-builder-ops-v2.md §13.1]
- PII minimization: don't decrypt lead name/phone for the execution view unless required. [Source: privacy constraints, architecture.md PII discipline]

## References
- [Source: epics.md#Story 16.3; architecture-builder-ops-v2.md §6, §13.1]
