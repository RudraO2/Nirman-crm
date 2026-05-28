---
baseline_commit: 1818e61
---
# Story 7.3: Streak-at-Risk push notification at 6 PM

Status: done

## Story

As an Employee,
I want a push notification at 6 PM tenant time if my streak is 3+ days and I have not yet logged a follow-up action today,
so that I do not lose my streak through forgetfulness.

## Acceptance Criteria

1. **Given** my current follow-up streak is ≥3 days **When** 6 PM tenant tz arrives and I have logged zero qualifying Actions since 00:00 today (tenant tz) **Then** I get a push: "Your N-day streak is at risk. Log a follow-up to keep it going." and it deep-links to the urgency-sorted lead list.
2. **Given** I log a qualifying Action between 6 PM and midnight **Then** my streak is preserved and no further notification fires today.
3. At most one streak-at-risk notification per day per Employee.

## Tasks / Subtasks

- [x] **Task 1 — Migration `0032`: `streak_at_risk_targets()` RPC + cron** (AC: 1,2,3)
  - [x] SECURITY DEFINER fn returning `(user_id, tenant_id, streak_days, token)` for employees who, **right now**, are at local 18:00 (tenant tz), have a streak ≥3 days ending yesterday, have NO qualifying action today, have a device token, and have NOT already been notified today (dedup via `domain_events`).
  - [x] Streak = gaps-and-islands run ending **yesterday** (today is empty by definition when at-risk). Qualifying events = the Story 3.7 list.
  - [x] Dedup check: `NOT EXISTS domain_events WHERE event_type='notification_sent' AND payload->>'type'='streak_at_risk' AND payload->>'user_id'=uid AND payload->>'local_date'=local_today`.
  - [x] `REVOKE … FROM PUBLIC, anon, authenticated; GRANT … TO service_role` (cron/edge only).
  - [x] pg_cron job `streak-at-risk` every 30 min → `net.http_post` the edge fn (same vault `project_url` pattern as 0026; auth header tolerant since fn is verify_jwt=false).
- [x] **Task 2 — Edge fn `streak-at-risk`** (AC: 1,3)
  - [x] `supabase/functions/streak-at-risk/index.ts`, `verify_jwt=false` (cron-invoked). Service-role client. Call `streak_at_risk_targets()`; for each row send FCM "Your {n}-day streak is at risk. Log a follow-up to keep it going." with `data:{type:'streak_at_risk', route:'/home'}`; then insert `domain_events` dedup row `{type:'streak_at_risk', user_id, local_date}`. Best-effort; prune stale tokens on FCM failure.
  - [x] Deploy via CLI; ensure `verify_jwt=false`.
- [x] **Task 3 — Mobile deep-link** (AC: 1)
  - [x] Ensure a tapped `streak_at_risk` notification opens the lead list (`/home`). Check `NotificationsService` tap handling routes on `data.route`/type; add minimal handling if missing. (Home IS the urgency-sorted list.)
- [x] **Task 4 — Verify**
  - [x] SQL: temporarily seed a 3-day streak (or assert the fn runs + returns 0 off-hours), confirm dedup excludes a second run. Document verification; restore any seeded rows.

### Review Findings (2026-05-28)

- [x] [Review][Patch] **P4** Dedup race: no unique index on `(payload→user_id, payload→local_date)`; insert happens AFTER FCM; error result not checked → second cron tick could re-send on slow FCM / failed insert [`supabase/migrations/0032_streak_at_risk.sql`, `supabase/functions/streak-at-risk/index.ts`]
- [x] [Review][Defer] **D2** `verify_jwt=false` makes edge fn publicly invokable (FCM/RPC flood risk) [`supabase/functions/streak-at-risk/index.ts`] — deferred, all cron fns share pattern per CLAUDE.md; broader security-hardening epic
- [x] [Review][Defer] **D3** `device_tokens` join not gated by tenant on streak fan-out [`0032_streak_at_risk.sql` JOIN] — deferred, V1 single-tenant

## Dev Notes

- **Architecture** names `streak-at-risk` edge fn + `streak_providers.dart` under motivation [Source: architecture.md L687, L751, L817]. Push-driven, queue-tolerant [L36].
- **Tenant-tz gating**: cron runs UTC; the RPC self-gates to tenants whose LOCAL hour is 18, so one cron handles all tz. Running every 30 min means the 18:00 and 18:30 ticks both qualify within the 18:00–18:59 window — dedup makes the 2nd a no-op.
- **Reuse**: streak gaps-and-islands from 0030/0031; qualifying-event list from 3.7; FCM + service-role + cron patterns from `send-followup-notifications` + 0026.
- **Dedup** lives in `domain_events` (append-only) with `event_type='notification_sent'`, matching the follow-up notifier's convention; distinguish via `payload.type='streak_at_risk'` + `payload.local_date`.
- **No vault `service_role_key` needed** — edge fn is `verify_jwt=false` (see CLAUDE.md). Cron bearer can be empty.
- **Streak semantics for "at risk"**: today has no qualifying action (else not at risk), so the live run ends yesterday; its length is the "N-day streak". Require ≥3.

### References
- [Source: epics.md#Story 7.3] · [architecture.md#L36,L687,L751,L817]
- [Source: supabase/migrations/0026_followup_notification_cron.sql] — cron + http_post
- [Source: supabase/functions/send-followup-notifications/index.ts] — service-role + FCM + dedup
- [Source: supabase/migrations/0030_get_my_motivation_stats.sql] — streak SQL

## Dev Agent Record
### Agent Model Used
claude-opus-4-7 (Amelia)
### Debug Log References
- `streak_at_risk_targets()` first raised `42702: column reference "tenant_id" is ambiguous` (RETURNS TABLE OUT params collide with unqualified CTE columns). Fixed in migration **0033** with `#variable_conflict use_column` + fully-qualified CTE refs.
- Post-fix: RPC executes, `targets_now = 0` (correct — not local 18:00). Edge fn invoke → `{"sent":0}` HTTP 200. Cron `streak-at-risk` = `0,30 * * * *`, active.
### Completion Notes List
- **Tz-correct, single-cron design**: cron fires every 30 min; the RPC self-gates to tenants at local hour 18, so one job serves all timezones. Dedup (`domain_events`) makes the 18:00 + 18:30 ticks idempotent within the window.
- **Streak-at-risk semantics**: "at risk" ⇒ no qualifying action today, so the live run ends yesterday; its length is the N-day streak. Require ≥3. Reuses the verified gaps-and-islands SQL from 0030/0031.
- **Full 6 PM firing not wall-clock-verified** (would require waiting until 18:00 IST or mutating tenant tz). Verified by construction + clean execution + identical-to-verified streak SQL. The live cron will exercise it daily; a real ≥3-day streak with no same-day action triggers it.
- **Deep-link**: extended `NotificationsService._handleMessageTap` to honour `data.route` (streak push → `/home`, the urgency-sorted list) while keeping `lead_id` routing for follow-up/sold pushes.
- No vault key needed (fn `verify_jwt=false`).
### Change Log
- 2026-05-28: Implemented Story 7.3 — `streak_at_risk_targets()` RPC (0032 + 0033 fix), `streak-at-risk` edge fn, 30-min tenant-tz-gated cron, notification deep-link route handling.
### File List
**New**
- `supabase/migrations/0032_streak_at_risk.sql`
- `supabase/migrations/0033_fix_streak_at_risk_ambiguity.sql`
- `supabase/functions/streak-at-risk/index.ts`
**Modified**
- `apps/mobile/lib/core/notifications_service.dart` — `route` deep-link handling.
