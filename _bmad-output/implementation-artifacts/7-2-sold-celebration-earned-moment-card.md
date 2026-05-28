---
baseline_commit: 24969f2
---
# Story 7.2: Sold Celebration animation and earned-moment card

Status: done

## Story

As an Employee,
I want a celebration + earned-moment card when I mark a Lead Sold,
so that the moment feels significant and earned, not infantilizing.

## Acceptance Criteria

1. **Given** I change a Lead's status to Sold and save **When** it succeeds **Then** within 300ms a full-screen celebration triggers.
2. For 1.5s: confetti burst, "Closed!" text, the lead name.
3. Then (3s or until tap to dismiss): an earned-moment card showing — days from `lead_created` to now, count of `call_initiated` + `whatsapp_sent` + `followup_completed` events for this Lead, and one personal-record line **if applicable** (e.g. "Your fastest close this quarter" when days_to_close is the minimum among this Employee's closes this quarter, or "Your Nth close this month").
4. Admin receives a push notification: "[Employee Name] just closed [Lead Name]".
5. The celebration plays on this Employee's device only.

## Tasks / Subtasks

- [x] **Task 1 — Edge function `sold-celebrate-calc`** (AC: 3,4,5)
  - [x] `supabase/functions/sold-celebrate-calc/index.ts`. `verify_jwt=true`. Use `verifyJwtAndScope(req)` (`../_shared/auth.ts`) for caller `{actorId, tenantId, role}`; a separate service-role client (`SUPABASE_SERVICE_ROLE_KEY`) for cross-row reads + admin token lookup + FCM (mirror `send-followup-notifications`).
  - [x] Input `{ lead_id }`. Authorize: lead exists, `assigned_to_user_id = actorId`, `status='sold'`. Else 403/404 via `errorResponse`.
  - [x] Compute earned-moment (tenant tz from `tenants.timezone`, fallback Asia/Kolkata):
    - `days_to_close` = floor(now − `leads.created_at`) in whole days (min 0).
    - `action_count` = count of `lead_timeline` rows for this lead with `event_type IN ('call_initiated','whatsapp_sent','followup_completed')`.
    - `sold_this_month` = count of caller's leads with current status `sold` AND a `status_changed→sold` event this tenant-month (reuse 7.1 logic).
    - `is_fastest_quarter` = days_to_close ≤ MIN(days_to_close) over caller's leads closed (status_changed→sold) in the current tenant-quarter.
  - [x] `personal_record` (one line, priority order): fastest-quarter → "Your fastest close this quarter"; else if sold_this_month ≥ 2 → "Your {ordinal(sold_this_month)} close this month"; else null.
  - [x] Admin push: `SELECT token FROM device_tokens dt JOIN users u ON u.id=dt.user_id WHERE u.role='admin' AND u.tenant_id = <tenant>`; send via `sendFcmNotification` "{employee} just closed {lead}". Employee display name = `users.email_or_username`; lead name = decrypted? Use `leads.name` only if non-encrypted; otherwise omit/΄a lead΄ (see Dev Notes — lead name is PII-encrypted; pass a neutral label or the unencrypted `name` column if present). Dedup not required (one close = one event).
  - [x] Return `{ days_to_close, action_count, personal_record }` (200). Deploy via `supabase functions deploy sold-celebrate-calc`.
- [x] **Task 2 — Mobile model + repository** (AC: 3)
  - [x] `confetti` package dependency (`flutter pub add confetti`) — required for AC-2 burst. (Approved: story authorizes new infra.)
  - [x] `SoldCelebration` model (`features/motivation/data/models/sold_celebration.dart`): `int daysToClose, int actionCount, String? personalRecord`.
  - [x] `MotivationRepository.fetchSoldCelebration(leadId)` → `functions.invoke('sold-celebrate-calc', body:{lead_id})`, parse `data`. On failure, return a safe default (`daysToClose:0, actionCount:0, personalRecord:null`) so the celebration still shows (never block the moment).
- [x] **Task 3 — Celebration overlay** (AC: 1,2,3)
  - [x] `features/motivation/ui/sold_celebration_overlay.dart`: full-screen overlay (showGeneralDialog / Overlay). Phase 1 (1.5s): `ConfettiController` burst + "Closed!" + lead name. Phase 2: earned-moment card (days, actions, optional record line); auto-dismiss after 3s or on tap. Total open ≤ ~300ms after trigger (controller starts immediately; stats fetched in parallel and slotted into phase 2).
  - [x] Helper `showSoldCelebration(context, ref, {leadId, leadName})`.
- [x] **Task 4 — Wire trigger** (AC: 1,5)
  - [x] In `pending_outcome_sheet.dart`, after `submitCallOutcome(newStatus:'sold')` succeeds, call `showSoldCelebration(...)`. Also invalidate `myMotivationStatsProvider` + `myLeadsProvider`.
  - [x] If any other UI path sets status to sold (edit sheet / status changer), trigger there too. Grep for `'sold'` write paths.
- [x] **Task 5 — Tests**
  - [x] `sold_celebration_test.dart`: model parse, ordinals, personal-record priority, empty default.
  - [~] Overlay widget test SKIPPED — confetti `ConfettiController` ticker + `Future.delayed` phase/auto-dismiss timers make `pumpAndSettle` hang and leave pending timers. Overlay is presentational; logic (model + RPC) is unit-tested + live-verified. Visual confirmation is an on-device check.

### Review Findings (2026-05-28)

- [x] [Review][Patch] **P1** sold-celebrate-calc lead select missing `tenant_id` check; `error` from `.maybeSingle()` ignored [`supabase/functions/sold-celebrate-calc/index.ts` lead lookup block]
- [x] [Review][Patch] **P2** Sold celebration can double-fire — `wasSold` computed off stale `widget.lead`, `setState(_loading=true)` runs after [`apps/mobile/lib/features/leads/ui/pending_outcome_sheet.dart:_submit`, `edit_lead_sheet.dart:_save`]
- [x] [Review][Patch] **P5** `is_fastest_quarter` always true on first sale of quarter — self-inclusion in min + `<=` [`supabase/migrations/0031_get_sold_celebration.sql` v_min_quarter calc]
- [x] [Review][Patch] **P8** Overlay 4.5s timer can pop wrong route after manual dismiss; showGeneralDialog uses sheet context [`apps/mobile/lib/features/motivation/ui/sold_celebration_overlay.dart`]
- [x] [Review][Defer] **D8** `days_to_close=0` reads "0 days to close" on same-day close [`sold_celebration_overlay.dart` _stat] — deferred, cosmetic

## Dev Notes

- **Architecture** names this edge function `sold-celebrate-calc` and the overlay `sold_celebration_overlay.dart` under `lib/features/motivation/` [Source: architecture.md L683, L748, L854]. Optimistic celebration <300ms [L67, L75] — start the confetti controller immediately; do not await the network before showing phase 1.
- **Lead name is PII** — `leads` stores `name_encrypted`; there is also a plain `name` used by list RPCs after decryption. The app already has the decrypted lead name on the card (`LeadDetail`/`LeadListItem`), so pass `leadName` from the client into the overlay for display (don't re-decrypt). For the **admin push** body, prefer a neutral label ("a lead") OR the server-decrypted name only if a decrypt helper is readily reusable; do not log plaintext PII unnecessarily — keep the push body minimal. Decide in Dev Agent Record.
- **Caller/role**: `verifyJwtAndScope` returns role/tenant/actorId from JWT app_metadata [Source: create-lead/_shared/auth.ts]. Admin lookup uses service-role client (RLS bypass) — same pattern as `send-followup-notifications/index.ts`.
- **FCM**: `sendFcmNotification({token,title,body,data})` from `_shared/fcm.ts`; `FCM_SERVICE_ACCOUNT` secret is already set (see CLAUDE.md). Returns bool; ignore individual failures (best-effort), clean stale tokens optionally.
- **Sold/month/quarter buckets** in tenant tz — reuse the 7.1 migration patterns (`status_changed`+`payload->>'to'='sold'`, `now() AT TIME ZONE tz`).
- **Event types** confirmed present: `call_initiated, whatsapp_sent, followup_completed, status_changed` [Source: migrations grep].
- **Trigger path**: status→sold currently flows through `submit_call_outcome` (pending_outcome_sheet `_statuses` includes 'sold'). Confirm no other sold writer before finishing.
- **Deploy** edge fn via CLI (`supabase functions deploy`), NOT MCP. file-based discipline per CLAUDE.md.

### Project Structure Notes
- Extends `features/motivation/` (created in 7.1). New edge fn folder under `supabase/functions/`.

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Story 7.2]
- [Source: _bmad-output/planning-artifacts/architecture.md#L67,L75,L683,L748,L854]
- [Source: supabase/functions/send-followup-notifications/index.ts] — service-role + FCM pattern
- [Source: supabase/functions/create-lead/_shared/auth.ts] — verifyJwtAndScope
- [Source: supabase/migrations/0030_get_my_motivation_stats.sql] — tenant-tz sold/month logic

## Dev Agent Record

### Agent Model Used
claude-opus-4-7 (Amelia)

### Debug Log References

- Live verified (real user JWT): `get_sold_celebration` RPC → `{days_to_close:0, action_count:15, sold_this_month:1, is_fastest_quarter:true}` HTTP 200; `sold-celebrate-calc` edge fn → `{admin_notified:1}` HTTP 200 (admin push fanned out, FK embed `users→device_tokens` resolved). Test lead mutation fully restored (status `hot`, 0 leftover test events).
- Full mobile suite green; `flutter analyze` 0 errors.

### Completion Notes List

- **Architecture deviation (documented):** earned-moment STATS come from a new SECURITY DEFINER RPC `get_sold_celebration` (client-called, fast, SQL tz/quarter handling) rather than from the edge function. The `sold-celebrate-calc` edge fn does the admin push only. This keeps the visible card <300ms (no edge cold-start) while still sending the admin FCM server-side. Net effect matches all ACs.
- **Two sold paths wired**, not one: `pending_outcome_sheet` (call outcome → sold) AND `edit_lead_sheet` (status chip → sold). Both guard on a real transition (`widget.lead.status != 'sold'`) so re-saving an already-sold lead does not re-celebrate.
- **Admin push body** uses the client-passed decrypted lead name (admin can see tenant leads anyway); employee name = `users.email_or_username`. Best-effort; stale tokens pruned on FCM failure.
- **Offline/error resilient:** `fetchSoldCelebration` and `notifyAdminSold` swallow errors — the celebration always plays; the earned-moment card just shows zeros if the RPC is unreachable.
- **confetti ^** added as a dependency (AC-2). Overlay auto-dismisses at ~4.5s or on tap (phase 2), all timers `mounted`-guarded.
- Not yet eyeballed on device — confetti/animation is a visual on-device check (USB) at next `flutter run`.

### Change Log

- 2026-05-28: Implemented Story 7.2 — `sold-celebrate-calc` edge fn (admin push) + `get_sold_celebration` RPC (0031) + `SoldCelebration` model + `sold_celebration_overlay` (confetti + earned-moment) wired into both sold paths. Added model tests.

### File List

**New**
- `supabase/migrations/0031_get_sold_celebration.sql`
- `supabase/functions/sold-celebrate-calc/index.ts`
- `apps/mobile/lib/features/motivation/data/models/sold_celebration.dart`
- `apps/mobile/lib/features/motivation/ui/sold_celebration_overlay.dart`
- `apps/mobile/test/features/motivation/sold_celebration_test.dart`

**Modified**
- `apps/mobile/lib/features/motivation/data/motivation_repository.dart` — `fetchSoldCelebration` + `notifyAdminSold`.
- `apps/mobile/lib/features/leads/ui/pending_outcome_sheet.dart` — trigger celebration on sold outcome.
- `apps/mobile/lib/features/leads/ui/edit_lead_sheet.dart` — trigger celebration on edit→sold.
- `apps/mobile/pubspec.yaml` / `pubspec.lock` — add `confetti`.
