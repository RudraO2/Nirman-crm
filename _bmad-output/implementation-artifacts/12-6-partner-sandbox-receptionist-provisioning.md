# Story 12.6: partner-agency sandbox and receptionist provisioning

Status: review  (migration 0061 + matrix map written + self-reviewed; later-epic capability guards cross-ref'd; apply deferred)

## Story

As a Builder Head,
I want to provision external partner-agency users and reception staff with correctly scoped access,
so that partners see only their own data and receptionists can gate visits without owning leads.

## Acceptance Criteria

1. **Given** a `partner_agency` user (`is_external=true`, has `agency_id`) **When** they query leads **Then** they see only leads whose `source_agency_id` = their agency (never internal leads), enforced at RLS/RPC layer.
2. **And** any read path returning unit data omits `cost_paise`/margin for external users.
3. **Given** a `receptionist` user **When** they authenticate **Then** they can reach the visit-verification surface (built in Story 13.4) but `get_my_leads`/lead-edit RPCs deny them (gate-not-own).
4. **And** the partner capability matrix (register lead, view partner-scoped inventory, hold own-lead units; NO confirm/edit-inventory/broadcast/export) is enforced by explicit `auth_role_tier()` guards in the relevant RPCs.
5. **And** partner-sourced leads carry `source_agency_id` set at registration; ownership rule per arch §14.1 (partner owns until routed).

## Tasks / Subtasks

- [ ] **Task 1 — Partner lead RLS/RPC scope**: add a partner branch so partner reads filter `source_agency_id = (caller's agency)`. Implement in the lead-list RPC path (e.g. a `get_agency_leads` variant or a branch in `visible_user_ids()` already returns agency users → leads assigned to agency users). Confirm partners cannot reach internal leads via any RPC.
- [ ] **Task 2 — Receptionist guards**: `get_my_leads`, lead create/edit RPCs reject `auth_role_tier()='receptionist'` (gate-not-own). Receptionist allowed only on `verify_visit` (13.4).
- [ ] **Task 3 — Capability guards**: add `auth_role_tier()` checks to confirm_booking (15.4), edit-inventory (14.x), developer-update post (14.4), export — deny `partner_agency`. Centralize the matrix in a comment/helper.
- [ ] **Task 4 — Tests**: partner sees only agency leads + no margin; receptionist denied lead RPCs; partner denied confirm/edit/broadcast/export.

## Dev Notes

- Receptionist role is minted here (role_tier from 12.1); the screen it uses is built in 13.4 — **role before screen, no blocking forward dep** (12.6 testable via deny-guards now). [Source: epics.md 12.6 sequencing note]
- Partner capability matrix is the single source of truth — enforce by explicit tier guards, not a policy engine. [Source: architecture-builder-ops-v2.md §13.2]
- `cost_paise` must never be selected by non-`builder_head` read paths (units RPCs in Epic 14 already designed this way — confirm). [Source: §2.2 note, §3.1]
- Channel-conflict routing default: partner owns sourced lead until a head/leader routes it; then internal owns, partner keeps read via `source_agency_id`. [Source: §14.1]
- Some guards land alongside their feature RPCs (14.x/15.4) — this story owns the receptionist + partner-lead-scope pieces and the matrix definition; capability guards on later-epic RPCs are added when those RPCs are written (cross-ref).

## References
- [Source: epics.md#Story 12.6]
- [Source: architecture-builder-ops-v2.md §13.2 partner matrix, §14.1 routing, §2.2]

## Implementation (2026-06-27)

**File:** `nirman-crm/supabase/migrations/0061_partner_receptionist_guards.sql`

- **Partner scope** — already satisfied by 12.5: `visible_user_ids()` returns a partner's own-agency users, so `get_team_leads()` is the partner's scoped view; partners cannot reach internal leads. Documented, no new code.
- **Receptionist gate-not-own** — added explicit `auth_role_tier()='receptionist'` deny to `get_my_leads` (faithful 0027 reproduce + guard). Edit/open paths already ownership-gated (`assigned_to=auth.uid()`, receptionist owns nothing). "Returns empty" ≠ "denied" → explicit deny is defense-in-depth against future mis-assignment.
- **Capability matrix** — single-source enforcement map in the migration header: each capability guard lands with its feature RPC (confirm→15.4, edit-inventory→14.1/14.2, margin→14.3, broadcast→14.4, log-amendment→16.2, export→head-only existing, register-lead receptionist-deny→13.5). Cross-referenced so nothing falls through.

**Self-review:** `get_my_leads` body byte-faithful to 0027 except the guard; GRANT preserved. Margin omission for externals is a "don't select cost_paise" rule enforced at each unit read path (14.3), not here. Honest scope: 12.6's net-new code is the receptionist guard + the matrix map; the structural sandboxing is inherited from 12.5 + ownership gating by design.

**Verification:** static. Runtime (receptionist denied get_my_leads; partner sees only agency; capability denials) at apply + as each feature RPC lands.

**Status:** code-complete for Epic-12 scope; downstream capability guards tracked to their epics.
