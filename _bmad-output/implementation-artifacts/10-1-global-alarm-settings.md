---
baseline_commit: 9d48ce2
context:
  - _bmad-output/planning-artifacts/epics.md#Story 10.1
  - _bmad-output/planning-artifacts/architecture.md#Local persistence (Drift) / NFR-15
  - nirman-crm/apps/mobile/lib/features/settings/ui/settings_screen.dart
  - nirman-crm/apps/mobile/lib/core/notifications_service.dart
---
# Story 10.1: Employee configures global alarm settings

Status: done

## Story

As an employee,
I want a Settings screen where I turn the alarm on and choose how long before each follow-up it should ring,
so that I control whether and when I get an alarm without configuring every lead.

## Acceptance Criteria

1. **Given** a new **Settings → Follow-up Alarms** screen reachable from the app's settings/menu **When** I open it **Then** I see a master **Enable alarms** toggle (default off) and a multi-select list of lead-time offsets — **1 min, 5 min, 10 min, 30 min before**, plus a custom-minutes entry — where I may enable any combination.
2. **And** my selection persists locally on the device (survives app restart) and is read by the scheduling logic in Story 10.2.
3. **And** disabling the master toggle cancels all currently scheduled follow-up alarms (per Story 10.3) and stops new ones being scheduled.
4. **And** the screen explains the Android exact-alarm / full-screen permission and the iOS time-sensitive-notification limitation in plain language, with a button to grant the required OS permissions.
5. **And** if the OS denies the exact-alarm or notification permission, the screen surfaces a clear non-blocking warning ("alarms may be delayed or silent until you allow this in system settings") rather than failing silently.

## Tasks / Subtasks

- [x] **Task 1 — Add deps + feature scaffold** (AC: 1, 2)
  - [x] `pubspec.yaml`: add `shared_preferences: ^2.5.5` and `permission_handler: ^12.0.0`.
  - [x] New feature folder `features/alarms/` matching the existing feature-folder + Riverpod layout (`data/`, `data/models/`, `providers/`, `ui/`).
- [x] **Task 2 — Settings model + persistence** (AC: 1, 2)
  - [x] `AlarmSettings` immutable model: `enabled` (bool, default false) + `offsetsMinutes` (sorted unique `List<int>`). `copyWith`, value equality, JSON-less primitive encode (bool + `List<String>`).
  - [x] `AlarmSettingsRepository` over **`SharedPreferencesAsync`** (no in-memory cache → readable from the 10.2/10.3 background alarm isolate). Keys `alarms.enabled`, `alarms.offsets_minutes`. load / save / setEnabled / setOffsets.
- [x] **Task 3 — Permissions wrapper** (AC: 4, 5)
  - [x] `AlarmPermissions` service over `permission_handler`: `request()` asks `Permission.notification` + (Android) `Permission.scheduleExactAlarm`; `status()` reports current grant. iOS: notification only (exact-alarm is Android-only → reported as not-applicable, not denied).
  - [x] `openAppSettings()` passthrough for the permanently-denied path.
- [x] **Task 4 — Riverpod controller** (AC: 1, 2, 3)
  - [x] `@riverpod` `AlarmSettingsController` (AsyncNotifier) exposing `AlarmSettings` state; `toggleEnabled`, `setOffsetEnabled(minutes, on)`, `addCustomOffset(minutes)`. On enable→disable transition, call `AlarmScheduler.cancelAllAlarms()` (AC3 seam — see Dev Notes) and structured-log.
  - [x] `@riverpod` permission-status provider for the warning banner.
- [x] **Task 5 — UI screen** (AC: 1, 4, 5)
  - [x] `AlarmSettingsScreen`: master `SwitchListTile`, offset `FilterChip` row (1/5/10/30) + "Add custom" minutes dialog, plain-language permission explainer card + **Grant permissions** button, non-blocking warning banner when permission denied. Match Material patterns used in existing screens — no freestyle UI.
  - [x] Route `/settings/alarms` in `app_router.dart`; entry `ListTile` ("Follow-up Alarms") in `settings_screen.dart`.
- [x] **Task 6 — Android manifest permissions** (AC: 4)
  - [x] Add `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `VIBRATE`, `WAKE_LOCK` (boot already present from FCM). Declared now so 10.2 alarm firing has them; runtime-request flow lives in this story.
- [x] **Task 7 — build_runner + analyze** (AC: all)
  - [x] `dart run build_runner build --delete-conflicting-outputs`; `flutter analyze` at 0 errors.

## Dev Notes

### Persistence choice — `SharedPreferencesAsync`, not Drift
Architecture's "Local persistence (Drift)" decision is the NFR-15 **draft buffer for lead writes** (offline-safe lead data with Supabase sync) — not device preference flags. Alarm settings are a tiny device-local key/value pair with no server sync and no RLS surface (epic: "No tenant data leaves the device"). `shared_preferences` is the Flutter idiom for exactly this. Use the **`SharedPreferencesAsync`** API (not the legacy cached `SharedPreferences`) because Stories 10.2/10.3 read these offsets from a **background alarm isolate** (alarm fire / `BOOT_COMPLETED`), where a separate-isolate in-memory cache would be stale. `SharedPreferencesAsync` always hits platform storage → cross-isolate consistent.

### AC3 cancel-on-disable seam
The actual alarm scheduler/canceller is Story 10.2/10.3 work (needs the alarm package + native channel). To keep AC3 honest without pre-building 10.2, this story defines an `AlarmScheduler` abstraction with a logged **no-op default** (`features/alarms/data/alarm_scheduler.dart`). Disabling the master toggle calls `cancelAllAlarms()` and structured-logs `{event:'alarms_disabled', reason:'master_toggle_off'}`. Story 10.2 replaces the no-op with the real exact-alarm canceller behind the same interface — no controller change needed.

### Permissions
`permission_handler ^12`. Runtime requests: `Permission.notification` (Android 13+ POST_NOTIFICATIONS, iOS alert/sound) and `Permission.scheduleExactAlarm` (Android 12+ SCHEDULE_EXACT_ALARM; `USE_EXACT_ALARM` is auto-granted for alarm-clock apps on Android 13+). `USE_FULL_SCREEN_INTENT` is manifest-declared (auto-granted for alarm/call category). Denied/permanentlyDenied → non-blocking warning + "Open system settings" (AC5), never block the toggle. iOS has no exact-alarm concept → the explainer states the time-sensitive-notification degradation (consistent with the Epic 1.8 iOS-limitation pattern); iOS status keys off notification permission only.

### Structured logging
No shared log helper exists in the mobile codebase; use `dart:developer log()` with a structured map per the architecture convention, e.g. `log('${{'event':'alarm_settings_saved','enabled':e,'offsets':o}}')`. Schedule/cancel/fire `{lead_id, followup_at, offset_minutes, alarm_id}` logging is 10.2/10.3 scope; 10.1 logs settings save + cancel-on-disable.

### Offsets model
Canonical presets 1/5/10/30 min. Custom entry adds any positive int (deduped, sorted, capped sane e.g. ≤1440). Stored as `List<String>` under `alarms.offsets_minutes`. Empty offset set with `enabled=true` is allowed but means "no alarms scheduled" — 10.2 simply schedules nothing; the UI hints to pick at least one.

### Project structure
- New: `features/alarms/{data,data/models,providers,ui}` + `core` untouched.
- Reuse router + settings entry patterns (`context.go('/settings/alarms')`).
- No migration (device-local). No Supabase/edge changes.

### References
- [Source: epics.md#Story 10.1: Employee configures global alarm settings]
- [Source: epics.md#Epic 10 — device-scheduled local alarms, no new RLS surface, structured logs]
- [Source: nirman-crm/apps/mobile/lib/features/settings/ui/settings_screen.dart — settings entry pattern]
- [Source: nirman-crm/apps/mobile/lib/router/app_router.dart — GoRoute pattern]
- [Source: nirman-crm/apps/mobile/lib/core/notifications_service.dart — existing permission-request precedent]

## Review Findings

_Self-review (Blind Hunter + Edge Case Hunter + Acceptance Auditor lenses), 2026-05-30. All 5 ACs satisfied. No blocking/security findings. 2 trivial analyzer infos in new code auto-fixed (`activeColor`→`activeThumbColor`; const Row)._

- [x] [Review][Fixed] Deprecated `activeColor` on SwitchListTile → `activeThumbColor`; non-const warning Row → `const Row`. New alarm files now analyze 0 issues.
- [x] [Review][By-design] AC3 cancellation uses a logged no-op `AlarmScheduler` seam — the real exact-alarm canceller is Story 10.2/10.3 (needs the alarm package + native channel). Disable already calls `cancelAllAlarms()` + structured-logs; 10.2 overrides `alarmSchedulerProvider` with no controller change. Honest sequencing, not a defect.
- [x] [Review][Verified] `permission_handler_android 13.0.1` needs compileSdk 35 / minSdk 21 — app is compileSdk=flutter (35+), minSdk 26. No build landmine for 10.2.
- [x] [Review][Note→10.2] `USE_FULL_SCREEN_INTENT` is manifest-declared (auto-granted for alarm category); Android 14+ special-access prompt for full-screen intent is a 10.2 runtime concern, not 10.1.
- [x] [Review][Edge] Offsets normalize (sort/de-dupe/clamp 0<m≤1440) + string round-trip covered by unit tests (6/6 pass). `enabled=true` with empty offsets is allowed (UI hints to pick one; 10.2 schedules nothing).

## Dev Agent Record

### Agent Model Used
claude-opus-4-8 (Amelia)

### Completion Notes List
- New `features/alarms/` feature (model + repository + permissions + scheduler-seam + controller + UI), matching the existing feature-folder + Riverpod (`@riverpod`) patterns. `build_runner` codegen ran clean.
- Persistence via `SharedPreferencesAsync` (not legacy cached `SharedPreferences`) so the 10.2/10.3 background alarm isolate reads current offsets. Keys `alarms.enabled` / `alarms.offsets_minutes`.
- Settings UI: master `SwitchListTile` (default off), preset offset `FilterChip`s (1/5/10/30) + custom-minutes dialog, plain-language Android/iOS permission explainer, **Grant permissions** button (→ `Permission.notification` + Android `scheduleExactAlarm`), and a non-blocking warning banner when a permission is missing (AC5). iOS shows the time-sensitive-notification limitation text (Epic 1.8 pattern).
- AC3 disable→cancel wired through the `AlarmScheduler` seam (logged no-op now; real canceller lands in 10.2). Structured logs on settings-save and cancel-all per the architecture `{...}` convention.
- Manifest: added POST_NOTIFICATIONS, SCHEDULE_EXACT_ALARM, USE_EXACT_ALARM, USE_FULL_SCREEN_INTENT, VIBRATE, WAKE_LOCK (BOOT already present). No migration (device-local; epic-confirmed no new RLS surface).
- `flutter analyze`: 0 errors (new alarm files 0 issues). Unit tests `test/features/alarms/alarm_settings_test.dart`: 6/6 pass.

### File List

**New**
- `nirman-crm/apps/mobile/lib/features/alarms/data/models/alarm_settings.dart`
- `nirman-crm/apps/mobile/lib/features/alarms/data/alarm_settings_repository.dart` (+ `.g.dart`)
- `nirman-crm/apps/mobile/lib/features/alarms/data/alarm_scheduler.dart` (+ `.g.dart`)
- `nirman-crm/apps/mobile/lib/features/alarms/data/alarm_permissions.dart` (+ `.g.dart`)
- `nirman-crm/apps/mobile/lib/features/alarms/providers/alarm_settings_controller.dart` (+ `.g.dart`)
- `nirman-crm/apps/mobile/lib/features/alarms/ui/alarm_settings_screen.dart`
- `nirman-crm/apps/mobile/test/features/alarms/alarm_settings_test.dart`

**Modified**
- `nirman-crm/apps/mobile/pubspec.yaml` (+ `shared_preferences`, `permission_handler`)
- `nirman-crm/apps/mobile/lib/router/app_router.dart` (+ `/settings/alarms` route)
- `nirman-crm/apps/mobile/lib/features/settings/ui/settings_screen.dart` (+ Follow-up Alarms entry)
- `nirman-crm/apps/mobile/android/app/src/main/AndroidManifest.xml` (+ alarm/notification permissions)

## Change Log
- 2026-05-30: Story 10.1 spec created + implemented (Amelia autonomous runner). New `features/alarms/` settings (toggle + offsets + permissions UI), `SharedPreferencesAsync` persistence, AlarmScheduler cancel-on-disable seam, manifest perms. analyze 0 errors; 6/6 unit tests pass. → status review.
</content>
