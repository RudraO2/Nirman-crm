---
baseline_commit: 9d48ce2
context:
  - _bmad-output/planning-artifacts/epics.md#Story 10.3
  - _bmad-output/implementation-artifacts/10-2-fullscreen-ringing-alarm.md
  - _bmad-output/implementation-artifacts/10-1-global-alarm-settings.md
  - nirman-crm/apps/mobile/lib/features/alarms/data/alarm_scheduler.dart
  - nirman-crm/apps/mobile/lib/features/alarms/providers/alarm_settings_controller.dart
  - nirman-crm/apps/mobile/lib/features/leads/data/lead_repository.dart
  - nirman-crm/apps/mobile/lib/features/leads/providers/lead_providers.dart
  - nirman-crm/apps/mobile/lib/features/home/ui/home_screen.dart
---
# Story 10.3: Alarms stay in sync with the follow-up lifecycle and reboot

Status: review

## Story

As an employee,
I want alarms to appear, move, and disappear automatically as I create, reschedule, or finish follow-ups,
so that I never get an alarm for a follow-up that no longer exists or at the wrong time.

## Acceptance Criteria

1. **Given** the alarm-scheduling logic from Story 10.2 and a device with alarms enabled **When** a follow-up is **created** with a due date-time **Then** one alarm per enabled offset is scheduled for it.
2. **And When** a follow-up is **rescheduled**, its existing alarms are cancelled and re-scheduled against the new time.
3. **And When** a follow-up is **completed, cancelled, or its lead is archived/reassigned away**, all of that follow-up's pending alarms are cancelled.
4. **And When** the device **reboots** (`BOOT_COMPLETED`), the app re-schedules all alarms for still-pending future follow-ups, since OS alarms do not survive a restart.
5. **And** alarms whose computed fire time is already in the past at scheduling time are skipped (no immediate spurious ring).
6. **And** each schedule/cancel/reschedule is structured-logged with `{lead_id, followup_at, offset_minutes, alarm_id, reason}`.

## Tasks / Subtasks

- [x] **Task 1 — `AlarmSyncService.reconcile()` — the single source of truth** (AC: 1, 2, 3, 5)
  - [x] New `features/alarms/data/alarm_sync_service.dart` + `@riverpod` `alarmSyncService` provider. One idempotent method `reconcile({required String reason, List<LeadListItem>? leads})` (optional `leads` lets a caller reuse an already-loaded list).
  - [x] `reconcile()` reads `AlarmSettings`. If `!enabled` → `cancelAllAlarms` and return.
  - [x] If enabled: source = supplied leads or `getMyLeads()`, then **cancel-then-rebuild** via `cancelScheduledAlarms` + `scheduleForFollowUp` per lead with a non-null `nextFollowupAt` (`.toLocal()`; `planFollowUpAlarms` skips past offsets, AC5).
  - [x] Reconcile model supersedes per-event targeted scheduling — archived/reassigned leads fall out of `getMyLeads()`.
- [x] **Task 2 — Cancel that preserves a live snooze** (AC: 3)
  - [x] `cancelScheduledAlarms()` added to `AlarmScheduler`; `AlarmPackageScheduler` stops only future, non-snooze alarms (decodes payload `isSnooze`, compares `dateTime` vs now via `Alarm.getAlarms()`). Bulk `cancelAllAlarms` retained for master-toggle-off.
- [x] **Task 3 — Wire reconcile into every follow-up mutation site** (AC: 1, 2, 3)
  - [x] **Implemented via a single `myLeadsProvider` listener** (`home_screen.dart` `initState`, `listenManual` + `fireImmediately`) rather than per-site calls. Every mutation site (followup set, call outcome, mark dead/restore, share/reassign) already `invalidate(myLeadsProvider)`, so the listener reconciles for all of them with the freshly-loaded list passed in (no extra fetch). Simpler and impossible to forget a site. (See completion notes.)
- [x] **Task 4 — Reconcile on app open** (AC: 3, 4)
  - [x] The same listener's `fireImmediately` first emission reconciles with reason `'app_open'`, correcting drift from server-side changes while the app was closed.
- [x] **Task 5 — Reconcile on alarms (re)enable** (AC: 1)
  - [x] `AlarmSettingsController.setEnabled(true)` → `reconcile('alarms_enabled')`; `setOffset` (and `addCustomOffset` via it) → `reconcile('offsets_changed')` when enabled. `cancelAllAlarms` on disable kept.
- [x] **Task 6 — Reboot handling (verify, don't rebuild)** (AC: 4)
  - [x] No custom receiver — `alarm` package's native BootReceiver + `Alarm.init()` re-arm persisted alarms; app-open reconcile corrects drift.
  - [x] Manifest confirmed: `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` all present (10.2). **On-device reboot survival = manual verify (deferred to Rudra).**
- [x] **Task 7 — Tests + analyze** (AC: all)
  - [x] `test/features/alarms/alarm_sync_service_test.dart` — fake scheduler + fake sources: disabled→cancel-only; enabled→selective-cancel + schedule non-null only; null skipped; blank-name fallback; removed-lead not rescheduled; supplied-list-no-refetch. 25/25 alarms tests pass.
  - [x] `flutter analyze` 0 errors (pre-existing infos/withOpacity-deprecation noise only); `build_runner` regenerated (`clean` needed — stale cache had skipped the new `.g.dart`).

## Dev Notes

### Architecture decision — reconcile model over per-event targeted scheduling
The epic phrases 10.3 as per-event (schedule on create, cancel on complete, etc.). Implementing each event with surgical add/remove requires plumbing the lead **name** + the **old vs new** time into every write site and recomputing exact alarm ids to cancel. A **reconcile** (`cancel scheduled + rebuild from `getMyLeads()`) is simpler, idempotent, and self-healing: every lifecycle event reduces to "active-lead list changed → reconcile". Alarm volume is tiny (one user's active leads × ≤4 offsets), so cancel-all+rebuild cost is negligible. This is the recommended approach and is reflected in the tasks. It also **closes the 10.2 deferred "targeted per-lead cancel"** item — remove that line from `deferred-work.md` when this ships.

### Why `getMyLeads()` is the right source
`LeadListItem` already carries `name` and `nextFollowupAt` (lead_repository.dart:21, models/lead_model.dart:112). Archived (dead/sold/future) and reassigned-away leads are excluded from `get_my_leads()` server-side, so they automatically have no alarm after reconcile — that is exactly AC3 with no extra code. Shared-in leads: confirm whether `get_my_leads()` includes leads shared TO the user (Story 4.4) and decide if those should ring — default to "schedule for whatever `getMyLeads` returns" and note it.

### Boot + session constraint (important)
Reconcile calls Supabase (`getMyLeads`) and therefore needs a live session — fine for the app-open / settings / write-site triggers (all authenticated contexts). It is **not** run from a background `BOOT_COMPLETED` isolate (no session there). Reboot re-arming is handled entirely by the `alarm` package's persisted-alarm BootReceiver, and the next app-open reconcile fixes any drift. Document this as the boot strategy (mirrors the Story 10.2 / 1.8 platform-degradation honesty).

### Preserve ringing/snoozed alarms (Task 2)
A blunt `cancelAllAlarms` inside reconcile would also stop an alarm the user is actively snoozing. Guard it: reconcile cancels only future, non-snooze follow-up alarms. Snooze ids are distinguishable (`alarmIdFor(..., snooze: true)`); a currently-ringing alarm is in `Alarm.getAlarms()` with `ringing` state. Keep the bulk `cancelAllAlarms` only for master-toggle-off.

### Files
- New: `features/alarms/data/alarm_sync_service.dart` (+ `.g.dart`), test `test/features/alarms/alarm_sync_service_test.dart`.
- Update: `alarm_scheduler.dart` (add `cancelScheduledAlarms()` selective cancel), `alarm_settings_controller.dart` (reconcile on enable/offset change), `home_screen.dart` (app-open reconcile), and the follow-up write sites in `features/leads/ui/` (reconcile after mutation).
- No migration (device-local). No Supabase/edge changes.

### References
- [Source: epics.md#Story 10.3: Alarms stay in sync with the follow-up lifecycle and reboot]
- [Source: 10-2-fullscreen-ringing-alarm.md — AlarmScheduler API (scheduleForFollowUp/cancelAllAlarms), deferred targeted-cancel item this story closes]
- [Source: lead_repository.dart:255 setFollowup / :236 submitCallOutcome / :200 markLeadDead — follow-up write sites]
- [Source: lead_providers.dart:18 myLeadsProvider — reconcile source + invalidation seam]
- [Source: home_screen.dart:36 _HomeScreenState.initState — app-open reconcile seam]
- [Source: alarm package /gdelataillade/alarm — Alarm.init() reschedules persisted alarms; SharedPreferences persistence + native BootReceiver re-arm on Android reboot]

## Dev Agent Record

### Agent Model Used
claude-opus-4-8

### Completion Notes List
- **Reconcile model shipped as specced.** `AlarmSyncService.reconcile` is the single
  idempotent op: disabled → `cancelAllAlarms`; enabled → `cancelScheduledAlarms`
  (selective) + rebuild from active leads. Closes the 10.2 deferred targeted-cancel
  (struck through in `deferred-work.md`).
- **Task 3 deviation (deliberate, better):** instead of editing each follow-up write
  site, wired ONE `listenManual(myLeadsProvider)` in `home_screen.initState`. All
  mutation sites already `invalidate(myLeadsProvider)`, so the listener fires for
  create/reschedule/complete/status/share-away uniformly and passes the just-loaded
  list straight into `reconcile(leads:)` (no redundant `getMyLeads`). `fireImmediately`
  doubles as the Task-4 app-open reconcile (`reason: 'app_open'` on first emission,
  `'leads_changed'` after). Fewer touch-points, impossible to forget a site. The
  `alarm_sync_service.dart` header comment already anticipated this listener approach.
- **Session/boot constraint honored:** reconcile needs a live Supabase session, so it
  only runs from authenticated contexts (app-open, settings, lead-list changes). Reboot
  re-arm is the `alarm` package's native BootReceiver + `Alarm.init()`; next app-open
  reconcile heals drift. No background-isolate Supabase call.
- **AC5 (past-skip)** is enforced inside `planFollowUpAlarms` (already unit-tested in
  `alarm_planning_test`); reconcile forwards all non-null follow-ups and lets planning
  drop wholly-past ones (0 scheduled).
- **Snooze preservation (Task 2)** lives in `AlarmPackageScheduler.cancelScheduledAlarms`
  (plugin-backed: skips `isSnooze` payloads + alarms at/just-past fire time). Unit test
  asserts reconcile routes to the selective cancel, never the bulk one; the plugin-level
  skip is verified on-device.
- **Build gotcha:** new `@riverpod` provider's `.g.dart` was skipped by a stale
  build_runner cache (`wrote 0 outputs`); `dart run build_runner clean` then build fixed it.
- **Outstanding manual verify (Rudra):** alarms survive a device reboot on RMX5003.

### Code Review (2026-05-31) — clean, 2 patches applied
Adversarial review (correctness / edge-case / acceptance lenses). No blockers. Patched:
- **M1 — concurrent reconcile race:** added an in-flight serialization guard
  (`_running` chain) on `AlarmSyncService` so overlapping triggers (home listener /
  settings / app-open) run strictly in order instead of interleaving a cancel with a
  prior run's just-scheduled alarm. Provider made `keepAlive` so the guard state
  survives across `ref.read`s. Also makes the listener's fire-and-forget safe — the
  chain has a `catchError` that structured-logs `alarm_error/op:reconcile` (fixes L1).
- **M2 — AC6 logging:** threaded the lifecycle `reason` into `scheduleForFollowUp`
  (now `required`) so each `alarm_scheduled` line carries `{reason, lead_id,
  followup_at, offset_minutes, alarm_id}`; added a per-alarm `alarm_cancelled` log in
  `cancelScheduledAlarms` with the same fields. AC6 now fully met.
- **Tests:** +3 (cancel-before-schedule ordering, reason threading, M1 serialization).
  **28/28 alarms, 121/121 full suite green. analyze 0 errors.**
- **Accepted, not patched (low):** L2 stale past-alarm lingers in `getAlarms` until
  dismissed (harmless); L3 redundant reconcile on refresh emissions (idempotent);
  L4 AC4 reboot met via the `alarm` pkg BootReceiver dependency + manual device verify.

### File List
- NEW `apps/mobile/lib/features/alarms/data/alarm_sync_service.dart` (+ `.g.dart`)
- NEW `apps/mobile/test/features/alarms/alarm_sync_service_test.dart`
- MOD `apps/mobile/lib/features/alarms/data/alarm_scheduler.dart` (`cancelScheduledAlarms` selective cancel + abstract method)
- MOD `apps/mobile/lib/features/alarms/providers/alarm_settings_controller.dart` (reconcile on enable / offset change)
- MOD `apps/mobile/lib/features/home/ui/home_screen.dart` (myLeadsProvider listener → reconcile; app-open + lead-change)
- MOD `_bmad-output/implementation-artifacts/deferred-work.md` (closed 10.2 targeted-cancel item)
