# Story 13.4: reception verifies a visit by customer code

Status: review  (migration 0067 written + self-reviewed; reception screen + apply deferred)

## Story

As a receptionist,
I want to enter a customer code to verify a walk-in visit,
so that the visit is recorded against the right lead and the visit count increments.

## Acceptance Criteria

1. **Given** a `receptionist` (or `builder_head`) on the visit-verification screen **When** I enter/scan a customer code **Then** `verify_visit(p_code)` resolves the code to a lead in the same tenant, increments `visit_count`, and appends `visit_verified` + `visit_logged` Timeline events with the new ordinal.
2. **And** an invalid / wrong-tenant / unknown code is rejected with a clear message.
3. **And** the lead card shows the current visit ordinal ("2nd visit").
4. **And** a receptionist cannot open/edit lead detail beyond the verification action (gate-not-own, per 12.6).

## Tasks / Subtasks

- [ ] **Task 1 — `verify_visit(p_code)` RPC** (SECURITY DEFINER): guard `auth_role_tier() IN ('receptionist','builder_head')`; tenant via `auth_tenant_id()`; resolve `customer_code` → lead (tenant-scoped); `UPDATE leads SET visit_count = visit_count + 1`; log `visit_verified` + `visit_logged` (ordinal = new visit_count) via `log_timeline_event`.
- [ ] **Task 2 — Reception surface**: a minimal screen (mobile + optionally admin web) with a code input + result. Receptionist-gated.
- [ ] **Task 3 — Lead card** shows visit ordinal.
- [ ] **Task 4 — Tests**: valid code increments + logs; invalid/wrong-tenant rejected; receptionist denied lead-edit RPCs (cross-check 12.6 guards).

## Dev Notes

- Receptionist role minted in 12.1/12.6; this story builds the screen it uses. Verify the gate-not-own guards from 12.6 are in place (receptionist denied `get_my_leads`/edit). [Source: 12-6 story]
- `visit_count` column from 13.1. Feeds 13.7 funnel "Visited" (`visit_count > 0`). [Source: architecture-builder-ops-v2.md §5.1, FR-46]
- Timeline enum values `visit_verified`/`visit_logged` added in 13.3 Task 2 (shared enum migration).

## References
- [Source: epics.md#Story 13.4; architecture-builder-ops-v2.md §5.1 FR-44/46, §13.1 receptionist]

## Implementation (2026-06-27)

**File:** `nirman-crm/supabase/migrations/0067_verify_visit.sql`

- `verify_visit(p_code)` SECURITY DEFINER: guard `auth_role_tier() IN ('receptionist','builder_head')`; tenant-scoped; `upper(trim(code))` match `FOR UPDATE`; `visit_count++` + `last_action_at`; logs `visit_verified` + `visit_logged` with the new ordinal; invalid/unknown/wrong-tenant → `invalid_customer_code`. REVOKE PUBLIC/anon, GRANT authenticated.
- Mobile/web call `supabase.rpc('verify_visit',{p_code})` directly — no edge fn needed.

**Self-review:** receptionist can call this but is denied get_my_leads (12.6) — gate-not-own intact. PII never decrypted here (only count). Code normalized to uppercase to tolerate reception input. Timeline event values exist (added 0065).

**Deferred:** reception check-in screen (code input + result) on mobile/admin. Apply.

**Status:** backend code-complete, awaiting apply + screen.
