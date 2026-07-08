# Story 13.5: 90-day agent-lock dedup with reclaim-in-place

Status: review  (migration 0066 + edge fn rework written + self-reviewed; HIGH-risk; apply deferred)

## Story

As a sales organisation,
I want a registered lead locked to its agent for 90 days then reclaimable if inactive,
so that leads aren't permanently frozen but aren't poached while actively worked.

## Acceptance Criteria

1. **Given** the reworked `create_lead_with_pii` **When** a phone is registered **Then** the function `SELECT … FOR UPDATE` by `phone_hash`; if absent it inserts and sets `lock_started_at = now()`, owner = caller.
2. **And** if a matching lead is locked (`now() < lock_started_at + 90d` AND `last_action_at > now() - 30d`), save is blocked with `duplicate_lead` whose payload includes owner username + `unlock_at`.
3. **And** if reclaimable (90d elapsed OR inactive ≥30d), the existing row is reassigned to caller, `lock_started_at` reset, status `warm`, and `lead_reclaimed` event logged (old→new owner).
4. **And** `leads_tenant_phone_hash_unique` remains (race backstop).
5. **And** migration backfills `lock_started_at = now()` for ALL existing leads (NOT `created_at`) — no historic lead reclaimable on day one.
6. **And** `assign_lead` takes the same `FOR UPDATE` row lock so a manual reassign cannot race a reclaim.

## Tasks / Subtasks

- [ ] **Task 1 — Migration `0064_dedup_rework.sql`**: `CREATE OR REPLACE create_lead_with_pii` replacing blind-insert+catch-`unique_violation` with `SELECT … FOR UPDATE` by `(tenant_id, phone_hash)` then branch (insert / block / reclaim) per arch §5.2. Keep all encrypt/timeline/return logic.
- [ ] **Task 2 — Backfill**: `UPDATE public.leads SET lock_started_at = now() WHERE lock_started_at IS NULL`. **Explicitly `now()`, never `created_at`** (party fix — prevents day-one mass reassignment).
- [ ] **Task 3 — `assign_lead` lock**: ensure it `SELECT … FOR UPDATE`s the lead before reassign (it already does for the lead row — confirm + ensure same predicate as reclaim).
- [ ] **Task 4 — Apply + tests**: locked phone blocked with owner+unlock_at; 91-day-old reclaimed; 30-day-inactive reclaimed; concurrent create vs assign serialize (no last-writer-wins); backfilled leads not reclaimable at T+0.

## Dev Notes

- **This is the HIGH-risk migration (arch §10 flag 1).** The reclaim path reassigns a LIVE row — get the backfill right or it silently reassigns owned leads. Backfill `now()` is non-negotiable. [Source: architecture-builder-ops-v2.md §5.2 REVISED, §10 flag 1]
- Keep the `duplicate_lead` error code (callers + mobile rely on it); add `unlock_at`/owner to its payload. [Source: 0016, errors.ts]
- Excel import (13.6) must adopt the same lock-aware logic — do 13.5 then 13.6. [Source: §5.2 excel-import note]
- 90d window + 30d inactivity are tenant-configurable (default constants for V2). [Source: A-12]
- Coordinate with 13.2 (secondary-phone capture also edits this RPC) — land 13.2 first, 13.5 extends.

## References
- [Source: epics.md#Story 13.5; architecture-builder-ops-v2.md §5.2, §10 flag 1, A-12]
- [Source: 0016_create_lead_with_pii.sql, 0010_add_phone_hash_unique.sql, 0054 assign_lead]

## Implementation (2026-06-27) — HIGH-risk story

**Files:** `nirman-crm/supabase/migrations/0066_dedup_reclaim.sql` · reworked `supabase/functions/create-lead/index.ts` · arch §15/§15.1 corrections.

**Key correction vs spec:** the unique constraint was ALREADY dropped by 0016 and is **NOT re-added** (legacy admin-override duplicate rows would make `ADD CONSTRAINT` fail; can't be `NOT VALID`). Atomicity instead comes from `SELECT … FOR UPDATE` inside the fn — the arch's original §5.2 intent.

- `0066`: backfill `lock_started_at = now()` for all existing leads (**NOT created_at** — the party-review fix; prevents day-one mass reassignment). DROP 17-arg + CREATE 18-arg `create_lead_with_pii` (adds `p_force_reclaim`). Logic: `SELECT … FOR UPDATE` the oldest phone-row; if locked (`now() < lock_started_at + 90d` AND `last_action_at > now()-30d`) AND not admin-force → `RAISE duplicate_lead` (DETAIL = owner + unlock_at); else **reclaim-in-place** (reassign same row, reset lock, status warm, log `lead_reclaimed`, return existing id); else new-lead insert (sets `lock_started_at=now()`, customer_code). GRANT re-issued.
- `create-lead` edge fn: dropped its own blocking pre-check (fn is authoritative); kept a non-admin-override guard; passes `p_force_reclaim = override && admin`; on `duplicate_lead` error does an owner lookup for the friendly "locked under [owner]" message; removed the stale `duplicate_override` logging + `existing` references.

**Self-review:** backfill `now()` verified (the one thing that must not be created_at). Reclaim returns the existing id → edge fn keeps the lead's customer_code. New-lead path fetches pii_key only after the dedup branch (reclaim needs no crypto). `v_is_admin` from JWT role. No phone-unique constraint relied upon. project_ids insert on reclaim is non-fatal (PK conflict caught/warn).

**Deferred:** runtime tests — locked-block w/ owner+unlock_at, 91-day reclaim, 30-day-inactive reclaim, admin force-reclaim, day-one-not-reclaimable on backfilled data, concurrent register serialization. Apply.

**Status:** backend code-complete (highest-risk migration), awaiting apply + tests.
