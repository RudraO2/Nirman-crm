# Story 16.4: auto-notify on log and on status change

Status: review  (migration 0083 + edge fn written + smoke ALL PASS 2026-06-28; FCM deploy deferred)

## Implementation (2026-06-28)

**Reality correction (as 14.4):** no `pending_notifications` table — transport is `domain_events` + per-event FCM edge fn → `device_tokens`.

**File:** `nirman-crm/supabase/migrations/0083_amendment_notify.sql`
- **Producers as TRIGGERS on `amendments`** (so 0081/0082 RPCs stay untouched), both SECURITY DEFINER (authenticated lacks INSERT on domain_events): AFTER INSERT → `amendment_logged`; AFTER UPDATE OF status (when changed) → `amendment_status_changed` (payload carries `notify_user_id = logged_by`). Payloads carry only unit/lead/amendment IDs + status — **no PII** (AC3).
- `get_amendment_log_audience(amendment)` → execution-team user_ids (the "logged" recipients).

**File:** `nirman-crm/supabase/functions/send-amendment-notification/index.ts` (NEW) — service-role; kind `logged` → exec-team audience, kind `status_changed` → `logged_by`; fans out FCM (deep-link `amendment_id`, no PII), prunes stale tokens, emits `notification_sent`.

**Tested (local runtime):** log → 1 `amendment_logged` event; audience = 2 exec members; 0 PII keys in payload; status change → 1 `amendment_status_changed` event with `notify_user_id` = originating agent.

**Deferred:** `supabase functions deploy send-amendment-notification --no-verify-jwt` + invoke (server action or a domain_events drain); deep-link UI.

## Story

As a salesperson,
I want the execution team notified when I log an amendment, and to be notified back on progress,
so that the loop closes without manual chasing.

## Acceptance Criteria

1. **Given** the FCM dispatcher (Epic 3 pattern) **When** an amendment is logged **Then** every member of `tenant_execution_team` is notified within ~60s, deep-linking to the amendment.
2. **And** when the execution team changes status, the originating agent (`logged_by`) is notified.
3. **And** notifications carry no PII beyond unit/lead reference.
4. **And** notification delivery reuses `pending_notifications` (no new transport).

## Tasks / Subtasks

- [ ] **Task 1 — Notify on log**: `log_amendment` (16.2) enqueues `pending_notifications` rows for each `tenant_execution_team` member.
- [ ] **Task 2 — Notify on status change**: `set_amendment_status` (16.3) enqueues a notification to `amendments.logged_by`.
- [ ] **Task 3 — Deep links**: notification payload deep-links to the amendment detail (mobile + web).
- [ ] **Task 4 — Tests**: log → all execution members notified ≤60s; status change → agent notified; no PII in payload; dispatcher reused.

## Dev Notes

- Reuse `pending_notifications` + dispatcher (Decision 13 / Epic 3.6) — new producers only. [Source: 3-6 story; architecture-builder-ops-v2.md §6 FR-57]
- Closes the amendment lifecycle loop (Mary party review — execution team must be able to ack back). [Source: party review §c]

## References
- [Source: epics.md#Story 16.4; architecture-builder-ops-v2.md §6]
- [Source: 0007 pending_notifications, send-followup-notifications dispatcher]
