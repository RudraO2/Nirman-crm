# Story 15.3: auto-release expired holds via pg_cron

Status: review  (migration 0077 written + applied + sweep/TOCTOU/warn smoke ALL PASS 2026-06-28; pg_cron schedule guarded — fires on prod)

## Implementation (2026-06-28)

**File:** `nirman-crm/supabase/migrations/0077_release_expired_holds.sql`

- `release_expired_holds()` — `FOR UPDATE SKIP LOCKED LIMIT 500` (bounded, concurrent-tick-safe); per row **re-asserts `released_at IS NULL AND expires_at <= now()` inside the UPDATE** (TOCTOU), `IF NOT FOUND → CONTINUE`; same txn returns unit hold→available + `status_version+1`; logs `hold_expired` (new enum) + emits `emit_inventory_changed(unit,'release')` (reuses 14.5 producer → end-to-end notify). System fn (no JWT) → writes lead_timeline/domain_events directly with `actor_role='system'` (the mark_overdue_followups pattern; `log_timeline_event` needs a JWT so can't be used).
- `warn_expiring_holds()` — emits `hold_expiring` domain_event ~T-2h before expiry, once per hold (dedup via new `unit_holds.expiry_warned_at`).
- pg_cron: `release-expired-holds` (every min) + `warn-expiring-holds` (every 5 min), guarded by `pg_extension` check (skipped locally, fires on prod). Uses `$cron$` tags (the 0026 nested-`$$` fix).
- Grants: service_role only (REVOKE authenticated).

**Tested (local runtime):** expired hold released → unit available, outcome=expired; hold_expired timeline + inventory_changed emitted; non-expired hold untouched; **TOCTOU — a converted-at-boundary hold is NOT re-released (outcome stays converted, 2nd sweep released 0)**; warn fires once → hold_expiring event; dedup → 2nd warn pass releases 0 / event count stays 1.

**Deferred:** FCM dispatcher edge fn consuming hold_expiring/hold_expired domain_events; live pg_cron verification on prod after deploy.

## Story

As a Builder Head,
I want unconfirmed holds to auto-release at expiry,
so that inventory doesn't stay locked indefinitely.

## Acceptance Criteria

1. **Given** migration `0061` scheduling `release_expired_holds()` every minute via pg_cron **When** the sweep runs **Then** it selects expired active holds `FOR UPDATE SKIP LOCKED LIMIT 500` and releases each with a TOCTOU-safe `UPDATE unit_holds SET released_at=now(), outcome='expired' WHERE id=? AND released_at IS NULL AND expires_at <= now()` (never a blind release).
2. **And** on release the unit returns to `available` (same transaction) and a `hold_expired` Timeline event is logged.
3. **And** a "hold expiring" FCM warning is enqueued at ~T-2h before expiry.
4. **And** a confirm-vs-release race test asserts a hold confirmed at the expiry boundary is NOT released.
5. **And** the batch is bounded (LIMIT 500 — no unbounded sweep).

## Tasks / Subtasks

- [ ] **Task 1 — `release_expired_holds()`** per arch §4.3: loop `FOR UPDATE SKIP LOCKED LIMIT 500`; per row re-assert predicate in the UPDATE; `IF NOT FOUND THEN CONTINUE`; set unit `available` in same txn; log `hold_expired`.
- [ ] **Task 2 — pg_cron schedule**: `cron.schedule('release-expired-holds','* * * * *', ...)` (pattern of `process-overdue-followups`, `0026`).
- [ ] **Task 3 — Expiry warning**: second cron query enqueues `pending_notifications` for holds nearing `expires_at` (~T-2h), dedup so warned once.
- [ ] **Task 4 — Tests**: expired released + unit available; confirm-vs-release boundary (confirmed hold not released); bounded batch; concurrent cron ticks safe (SKIP LOCKED).

## Dev Notes

- **TOCTOU-critical**: never blind-release a row selected a moment earlier; re-assert `released_at IS NULL AND expires_at <= now()` in the UPDATE. [Source: architecture-builder-ops-v2.md §4.3, Amelia]
- pg_cron + pg_net already enabled + proven. [Source: CLAUDE.md; 0026_followup_notification_cron.sql]
- Reuse dispatcher for the warning (no new transport).

## References
- [Source: epics.md#Story 15.3; architecture-builder-ops-v2.md §4.3]
- [Source: 0026_followup_notification_cron.sql — pg_cron pattern]
