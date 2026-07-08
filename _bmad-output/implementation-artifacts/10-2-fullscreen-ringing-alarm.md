---
baseline_commit: 9d48ce2
context:
  - _bmad-output/planning-artifacts/epics.md#Story 10.2
  - _bmad-output/implementation-artifacts/10-1-global-alarm-settings.md
  - nirman-crm/apps/mobile/lib/features/alarms/data/alarm_scheduler.dart
  - nirman-crm/apps/mobile/lib/main.dart
  - nirman-crm/apps/mobile/lib/app.dart
  - nirman-crm/apps/mobile/lib/router/app_router.dart
---
# Story 10.2: Full-screen ringing alarm fires for a follow-up

Status: done

## Story

As an employee,
I want an alarm that actually rings and shows full-screen at each chosen offset before a follow-up,
so that I never miss a follow-up even with the app closed or the phone locked.

## Acceptance Criteria

1. **Given** alarms are enabled with one or more offsets (Story 10.1) and a follow-up exists with a due date-time (Epic 3.5) **When** the device clock reaches `followup_at − offset` for each enabled offset **Then** on Android the app fires an **exact alarm** (`SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM`) that shows a **full-screen intent** (`USE_FULL_SCREEN_INTENT`) over the lock screen, playing an alarm sound and vibration that continue until the user acts — fired correctly even when the app process is killed or the device is offline.
2. **And** the alarm screen shows the lead name, the follow-up time, and the offset (e.g. "in 10 minutes"), with **Snooze** and **Dismiss** actions.
3. **And** **Dismiss** stops the alarm; **Snooze** re-rings after a short fixed interval (5 min); tapping the alarm body opens that lead's detail screen.
4. **And** on **iOS**, because a clock-style full-screen alarm is not possible, the same trigger delivers a **time-sensitive (critical) local notification** with sound, and the AC is considered met by that degraded behavior (documented limitation, consistent with the Epic 1.8 iOS-platform-limitation pattern).
5. **And** multiple enabled offsets for the same follow-up each produce their own alarm.

## Tasks / Subtasks

- [x] **Task 1 — Add `alarm` package + replace the 10.1 no-op scheduler** (AC: 1, 5)
  - [x] `pubspec.yaml`: add `alarm: ^5.4.0`.
  - [x] Implement `AlarmPackageScheduler` (real Android impl) behind the existing `AlarmScheduler` interface from 10.1; `alarmScheduler` provider returns it on Android, keeps `NoopAlarmScheduler` elsewhere. The `alarm` package's own `AlarmSettings` type is import-aliased to avoid clashing with our device-settings model.
  - [x] `scheduleForFollowUp` sets one exact, full-screen, looping alarm per planned offset; device-default alarm sound (no licensed asset), `vibrate:true`, `androidFullScreenIntent:true`, fade-in enforced volume.
- [x] **Task 2 — Pure, testable planning logic** (AC: 1, 5)
  - [x] `data/alarm_planning.dart`: `planFollowUpAlarms()` → one `PlannedAlarm` per offset firing `followUpAt − offset`, skipping any whose fire time is already past (no spurious immediate ring).
  - [x] `alarmIdFor()` — deterministic positive 31-bit id (FNV-1a, not `String.hashCode`) from `(leadId, followUpAt, offset, snooze?)` so 10.3 can recompute ids to cancel/reschedule; snooze gets a distinct id.
  - [x] `humanOffsetLabel()` for the ring-screen "Rings 10 minutes before…" line; `kAlarmSnoozeInterval = 5 min`.
- [x] **Task 3 — Alarm payload model** (AC: 2, 3)
  - [x] `data/models/follow_up_alarm.dart`: `FollowUpAlarmPayload` (leadId, leadName, followUpAt, offsetMinutes, isSnooze) with JSON `encode()` / null-safe `tryDecode()` (alien/garbage payloads → null → ring natively without a ring screen) and `asSnooze()`.
- [x] **Task 4 — Full-screen ring UI** (AC: 2, 3)
  - [x] `ui/alarm_ring_screen.dart`: navy full-screen scaffold, lead name + formatted follow-up time + offset line; `PopScope(canPop:false)` so system-back can't silently leave the alarm sounding; **Snooze 5 min** / **Dismiss** buttons; tap body → dismiss + `go('/lead/:id')`.
  - [x] Snooze → `Alarm.stop` + re-set at `now + 5min` with a snooze-id payload; Dismiss → `Alarm.stop`.
- [x] **Task 5 — App wiring (cold-start + foreground)** (AC: 1, 2)
  - [x] `main.dart`: `await Alarm.init()` before `runApp`.
  - [x] `app.dart`: subscribe to `Alarm.ringing`; for each newly-ringing alarm with a decodable follow-up payload, push `/alarm-ring`; de-dupe via a shown-id set; cancel the subscription on dispose.
  - [x] `app_router.dart`: `/alarm-ring` route taking `AlarmRingArgs` via `state.extra`.
- [x] **Task 6 — Tests + analyze** (AC: all)
  - [x] `test/features/alarms/alarm_planning_test.dart`: fire-time, past-skip, empty-offsets, all-past, id determinism/uniqueness/snooze-collision, payload round-trip/`asSnooze`/garbage, offset label.
  - [x] `flutter analyze` clean on the feature + wiring files.

## Dev Notes

### Builds directly on the 10.1 seam — no controller churn
Story 10.1 deliberately shipped `AlarmScheduler` as a logged no-op with a real interface and a Riverpod provider. 10.2 only swaps the provider's Android branch to `AlarmPackageScheduler`; `AlarmSettingsController.setEnabled(false)` still calls `cancelAllAlarms()` through the same seam — now a real cancel-all instead of a log line. No controller or settings-UI change was required. [Source: 10-1-global-alarm-settings.md#AC3 cancel-on-disable seam]

### `alarm` package (`^5.4.0`)
Chosen because it bundles the exact-alarm + full-screen-intent + ring-until-stopped behavior we need, exposes an `Alarm.ringing` stream for the foreground/cold-start ring-screen push, and persists scheduled alarms across process death. Its exported `AlarmSettings` type collides with our device-settings model of the same name → imported `as alarm`. `Alarm.init()` must run before `runApp` (done in `main.dart`).

### Scheduling is invoked by 10.3, firing is this story
10.2 owns: building the alarm set (`planFollowUpAlarms`), firing/ringing it (`AlarmPackageScheduler.scheduleForFollowUp`), the ring screen, snooze/dismiss, and a real `cancelAllAlarms`. The *call sites* that schedule on follow-up create/reschedule/complete and re-schedule on `BOOT_COMPLETED` are **Story 10.3** scope. So in this story alarms can be scheduled (e.g. via the scheduler API / a manual hook) and will ring correctly; automatic lifecycle wiring lands in 10.3.

### iOS degradation (AC4)
Android-only real impl this story; `alarmScheduler` returns `NoopAlarmScheduler` on iOS (logs intent, no OS ring). The epic's iOS path is a **time-sensitive critical local notification** — that delivery is **not yet implemented here** and is carried as deferred work for the iOS build (consistent with the Epic 1.8 iOS-limitation pattern). The app currently ships Android only, so this does not block the Android release. **Reviewer: confirm whether AC4 must be satisfied now or can stay deferred until an iOS build exists.**

### Permissions
All required manifest permissions (`SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `POST_NOTIFICATIONS`, `VIBRATE`, `WAKE_LOCK`) were declared in Story 10.1; runtime grant flow also lives in 10.1's settings screen. Android 14+ full-screen-intent special-access was flagged in 10.1 review as a 10.2 runtime concern — `androidFullScreenIntent:true` is set; the alarm/clock category auto-grant should cover it (verify on device).

### Structured logging
Every schedule/cancel/dismiss/snooze logs `{event, lead_id, followup_at, offset_minutes, alarm_id, ...}` via `dart:developer log()` per the architecture convention, matching the 10.1 log shape.

### Project structure
- New: `features/alarms/data/alarm_planning.dart`, `features/alarms/data/models/follow_up_alarm.dart`, `features/alarms/ui/alarm_ring_screen.dart`, `test/features/alarms/alarm_planning_test.dart`.
- Updated: `features/alarms/data/alarm_scheduler.dart` (no-op → real Android impl), `main.dart`, `app.dart`, `router/app_router.dart`, `pubspec.yaml` (+`alarm`).
- No migration (device-local; epic-confirmed no new RLS surface).

### References
- [Source: epics.md#Story 10.2: Full-screen ringing alarm fires for a follow-up]
- [Source: epics.md#Epic 10 — device-scheduled local alarms, Android full-screen + iOS time-sensitive degradation]
- [Source: 10-1-global-alarm-settings.md — AlarmScheduler seam, manifest perms, permission flow]
- [Source: nirman-crm/apps/mobile/lib/app.dart — Alarm.ringing listener / ring-screen push]
- [Source: nirman-crm/apps/mobile/lib/router/app_router.dart — /alarm-ring GoRoute]

## Review Findings

_Code review 2026-05-30 — 3 adversarial layers (Blind Hunter, Edge Case Hunter, Acceptance Auditor). 4 patch (all fixed), 4 defer, 3 dismissed as noise. Router redirect + extra-cast findings verified against actual `app_router.dart`. Post-fix: analyze 0 issues, 20/20 alarm tests pass._

- [x] [Review][Patch][Fixed] `/alarm-ring` not exempt from the `session==null → /login` auth redirect — ring screen was lost on cold-start (app killed/locked = the exact scenario the feature exists for). Fix: added `isAlarmRingRoute` exemption to the no-session redirect [app_router.dart:50]
- [x] [Review][Patch][Fixed] `state.extra as AlarmRingArgs` crashed when extra is null on OS route-restoration. Fix: builder now type-checks `extra` and falls back to `HomeScreen` instead of a null cast [app_router.dart:95]
- [x] [Review][Patch][Fixed] Snooze id hardcoded offset 0 → two snoozed offsets of the same follow-up collided. Fix: snooze id now derives from `payload.offsetMinutes`; `asSnooze()` retains the offset. Regression test added [alarm_scheduler.dart:163, follow_up_alarm.dart:32]
- [x] [Review][Patch][Fixed] No try/catch around `alarm.Alarm.set/stop/getAlarms`. Fix: all four scheduler methods wrap plugin calls, logging `{event:'alarm_error', op, error}` instead of crashing; schedule count now reflects only successes [alarm_scheduler.dart]
- [x] [Review][Defer] AC4 iOS time-sensitive critical notification NOT implemented (iOS = no-op scheduler, no degraded path) — deferred to first iOS build; app currently ships Android-only so non-blocking. AC4 = not-met, not satisfied [alarm_scheduler.dart:215]
- [x] [Review][Defer] `cancelAllAlarms` is global (stops every lead's alarms) — correct for its only caller (master-toggle-off, AC3) but Story 10.3 must add a targeted per-lead cancel before using it on single-lead reschedule [alarm_scheduler.dart:99]
- [x] [Review][Defer] Multiple offsets firing in one stream emission stack multiple ring screens; in-memory `_shown` re-pushes a still-ringing alarm after process relaunch — needs a single-active-ring guard [app.dart:31]
- [x] [Review][Defer] Payload decode failure + foreign-alarm path ring natively but log nothing — observability gap (silent) [follow_up_alarm.dart:60, app.dart:37]
- [x] [Review][Dismiss] "Untyped dynamic scheduling params" (Blind Hunter) — false positive; real code fully types `String leadId, String leadName, DateTime followUpAt`
- [x] [Review][Dismiss] FNV-1a 31-bit id collision — astronomically low at CRM volume and deterministic ids are required by Story 10.3's recompute-to-cancel; accepted
- [x] [Review][Dismiss] `humanOffsetLabel` >1440 / timezone-DST — offsets normalized ≤1440 in 10.1; fire-time math is local-vs-local; non-issue

## Dev Agent Record

### Agent Model Used
claude-opus-4-8 (Amelia)

### Completion Notes List
- Real Android `AlarmPackageScheduler` over `alarm ^5.4.0` replaces the 10.1 no-op behind the unchanged `AlarmScheduler` interface; exact alarm + full-screen intent + loop-until-acted + enforced fade-in volume. (AC1, AC5)
- Pure `alarm_planning.dart` (no plugin imports) computes fire times, skips past offsets, derives stable FNV-1a 31-bit alarm ids, and labels offsets — fully unit-tested. (AC1, AC5)
- `FollowUpAlarmPayload` JSON-encodes into the alarm so the ring screen rebuilds after process death; `tryDecode` null-guards alien payloads. (AC2)
- `AlarmRingScreen`: lead name + time + offset, Snooze 5 min / Dismiss, tap-body → lead detail, `PopScope(canPop:false)`. (AC2, AC3)
- Wiring: `Alarm.init()` in `main.dart`; `Alarm.ringing` listener in `app.dart` pushes `/alarm-ring` for newly-ringing follow-up alarms (de-duped), cancelled on dispose; `/alarm-ring` route added. (AC1, AC2)
- **Open for review:** AC4 (iOS time-sensitive critical notification) NOT implemented — iOS stays on the no-op scheduler; carried as deferred iOS work. Automatic schedule/reschedule/boot wiring is Story 10.3.

### File List

**New**
- `nirman-crm/apps/mobile/lib/features/alarms/data/alarm_planning.dart`
- `nirman-crm/apps/mobile/lib/features/alarms/data/models/follow_up_alarm.dart`
- `nirman-crm/apps/mobile/lib/features/alarms/ui/alarm_ring_screen.dart`
- `nirman-crm/apps/mobile/test/features/alarms/alarm_planning_test.dart`

**Modified**
- `nirman-crm/apps/mobile/lib/features/alarms/data/alarm_scheduler.dart` (no-op → real Android `AlarmPackageScheduler`)
- `nirman-crm/apps/mobile/lib/main.dart` (+ `Alarm.init()`)
- `nirman-crm/apps/mobile/lib/app.dart` (+ `Alarm.ringing` listener → ring screen)
- `nirman-crm/apps/mobile/lib/router/app_router.dart` (+ `/alarm-ring` route)
- `nirman-crm/apps/mobile/pubspec.yaml` (+ `alarm: ^5.4.0`)

## Change Log
- 2026-05-30: Story 10.2 implemented (full-screen ringing alarm: real Android scheduler, planning logic, payload, ring screen, app wiring, planning tests). Story spec authored post-implementation to reflect actual state. → status review (pending code-review; AC4/iOS deferred decision open).
