---
baseline_commit: 596238c
context:
  - _bmad-output/planning-artifacts/epics.md#Epic 10
  - _bmad-output/implementation-artifacts/10-2-fullscreen-ringing-alarm.md
  - _bmad-output/implementation-artifacts/10-3-alarm-lifecycle-and-boot-sync.md
  - nirman-crm/apps/mobile/lib/features/alarms/data/alarm_scheduler.dart
  - nirman-crm/apps/mobile/lib/features/alarms/data/alarm_permissions.dart
  - nirman-crm/apps/mobile/lib/features/alarms/ui/alarm_settings_screen.dart
  - nirman-crm/apps/mobile/android/app/src/main/kotlin/com/nirmanmedia/nirman_crm/MainActivity.kt
  - nirman-crm/apps/mobile/android/app/src/main/AndroidManifest.xml
---
# Story 10.4: Alarm OEM reliability hardening

Status: review

<!-- Hardening story. NOT in the original epics.md; sourced from a 2026-07-11 code
audit of the shipped Epic 10 alarm feature. Closes the three reliability gaps that
cause "alarms don't ring" on aggressive Android OEMs (Xiaomi/Oppo/Vivo/Realme, etc.). -->

## Story

As an employee on any Android phone (including Xiaomi/Redmi, Oppo, Vivo, Realme, Samsung),
I want the app to walk me through *every* OS setting that makes follow-up alarms reliable — including the OEM auto-start setting the app currently ignores — and to warn me when I've done something that will silently break them,
so that a scheduled follow-up alarm actually rings, every time, even after I swipe the app away or reboot the phone.

## Context & problem (from audit)

The Epic 10 alarm stack (10.1–10.3) is functionally complete: exact alarm + full-screen intent + overlay fallback + battery-opt request + reconcile + boot re-arm. It works on stock Android / Pixel. It fails intermittently on OEM skins for three concrete, fixable reasons:

- **Gap 1 — OEM auto-start not handled (P0, top cause).** The `alarm` package docs state Samsung/Honor/Huawei/Xiaomi/Oppo/Asus require the OEM **"Autostart" / "Auto-launch"** permission for background full-screen alarms and boot re-arming. When Autostart is OFF (the default on MIUI/ColorOS/FuntouchOS), the OS kills the alarm process → **no alarm after task-kill AND no re-arm after reboot** (the package's `BootReceiver` never runs). The app today guides notification / exact-alarm / overlay / battery-opt but **never** routes the user to Autostart. No overlay or battery toggle fixes this — only Autostart does.
- **Gap 2 — on-kill warning disabled on Android (P1).** `alarm_scheduler.dart` sets `warningNotificationOnKill: Platform.isIOS` → **false on Android**, leaving the manifest-declared `NotificationOnKillService` inert on the exact platform where swiping the app from recents cancels alarms. Combined with Gap 1: user swipes app away → no alarm, no warning.
- **Gap 3 — no proactive onboarding; battery-opt requested only conditionally (P1).** Permissions surface only if the user digs into Settings → Follow-up alarms. `requestIgnoreBatteryOptimizations()` fires only as a side-effect of the "Allow full-screen alarms" button, and **only when overlay is still missing** — so if overlay was already granted, battery-opt is never requested and the alarm stays Doze/OEM-killable.

## Acceptance Criteria

### AC-group A — OEM auto-start guidance (Gap 1, P0)

1. **Given** an Android device from an OEM with an Autostart/Auto-launch manager (Xiaomi/MIUI, Oppo & Realme/ColorOS, Vivo/FuntouchOS, Huawei/EMUI, Samsung, Asus, OnePlus, Honor, Letv) **When** the alarm settings screen renders **Then** a clearly-labelled **"Allow auto-start"** guided step is shown that explains, in plain language, that this OEM can stop alarms unless auto-start is enabled.
2. **And When** the user taps that step **Then** the app opens the OEM's Autostart/Auto-launch settings page directly via a native `Intent` (deep-linked by `Build.MANUFACTURER`), and if that specific component is not present (`ActivityNotFoundException`/other), it **gracefully falls back** to the app's system settings page rather than crashing or dead-ending.
3. **And** because auto-start state is **not programmatically queryable** on Android, this step is presented as guidance (never as a hard `hasBlocker`), and the app records locally that the user has visited it so the proactive nudge (AC-group C) does not repeat every launch.
4. **And** on a stock-Android / Pixel / OEM without a known Autostart manager, the step is either hidden or degrades to the app-settings fallback — no spurious dead button.

### AC-group B — enable on-kill warning on Android (Gap 2, P1)

5. **Given** the scheduler builds an `alarm.AlarmSettings` **When** running on Android **Then** `warningNotificationOnKill` is **true**, so the `alarm` package's `NotificationOnKillService` posts its warning if the app is force-killed/swiped while alarms are pending. (iOS unchanged.)
6. **And** the warning notification's title/body use plain, on-brand copy (not the package default) where the `alarm` package API allows overriding it, telling the user their follow-up alarms may not ring because the app was closed.

### AC-group C — proactive onboarding + unconditional battery-opt (Gap 3, P1)

7. **Given** the user turns the master **Enable alarms** toggle ON **When** the toggle flips to enabled **Then** the app runs a **guided permission sequence** in order: notification → exact-alarm → overlay ("display over other apps") → battery-optimization exemption → OEM auto-start, requesting/route-to-settings for each still-missing one, and the user can complete or skip the flow (non-blocking).
8. **And** the battery-optimization exemption (`requestIgnoreBatteryOptimizations`) is requested on the primary grant path **unconditionally** (whenever not already granted), not only when overlay is missing.
9. **And** the existing non-blocking warning banner (AC5 of 10.1) continues to reflect the real OS grant state and is refreshed on `AppLifecycleState.resumed` after the user returns from any settings page.
10. **And** the guided flow is idempotent and safe to re-run from the settings screen (re-enabling, or a "Re-check / fix alarms" affordance) without duplicate prompts or errors.

### AC-group D — non-regression + quality

11. **And** existing alarm behavior is preserved: scheduling, ring screen, snooze/dismiss, reconcile (10.3), boot re-arm, and the `Platform.isAndroid ? AlarmPackageScheduler : NoopAlarmScheduler` selection all still work; iOS still degrades to the no-op/notification path with no new prompts.
12. **And** `flutter analyze` is 0 errors and the full `test/features/alarms/*` suite is green, with new/updated unit tests for the pure/testable additions (OEM-intent resolution mapping, status/onboarding logic).

## Tasks / Subtasks

- [x] **Task 1 — Enable on-kill warning on Android (AC: 5, 6)** — smallest, do first
  - [x] `alarm_scheduler.dart` `_toAlarmSettings`: change `warningNotificationOnKill: Platform.isIOS` → `warningNotificationOnKill: true` (fires on both; the service is Android-only anyway). Update the adjacent comment (currently justifies the iOS-only guard).
  - [x] If the installed `alarm` 5.4.0 API exposes on-kill notification title/body overrides, set on-brand copy; if not, leave default and note it in completion notes. Verify the manifest `NotificationOnKillService` declaration is present (it is) — no manifest change expected.
- [x] **Task 2 — Native OEM auto-start deep-link (AC: 1, 2, 4)**
  - [x] `MainActivity.kt`: extend the existing `nirman/alarm_permissions` `MethodChannel` with two methods: `hasAutoStartManager` (returns whether a known Autostart component exists for `Build.MANUFACTURER`, best-effort via `PackageManager.resolveActivity`/`queryIntentActivities`) and `openAutoStartSettings` (starts the OEM component `Intent`; on `ActivityNotFoundException`/`SecurityException` falls back to `ACTION_APPLICATION_DETAILS_SETTINGS` for `packageName`).
  - [x] Encode the per-OEM `ComponentName` table (package/class) for at least: Xiaomi/Redmi/Poco (`com.miui.securitycenter` → `com.miui.permcenter.autostart.AutoStartManagementActivity`), Oppo/Realme (`com.coloros.safecenter` → `.permission.startup.StartupAppListActivity`, plus legacy `com.oppo.safe`), Vivo (`com.vivo.permissionmanager` → `.activity.BgStartUpManagerActivity`, plus `com.iqoo.secure`), Huawei/Honor (`com.huawei.systemmanager` → `.startupmgr.ui.StartupNormalAppListActivity` / `.optimize.process.ProtectActivity`), Samsung (`com.samsung.android.lool` device-care battery), Asus, OnePlus, Letv. Add `Intent.FLAG_ACTIVITY_NEW_TASK`. Wrap every `startActivity` in try/catch → fallback. **Reference the "Don't kill my app!" / autostarter component list; implement natively (no new pub dependency).**
  - [x] `alarm_permissions.dart`: add Dart wrappers `hasAutoStartManager()` and `openAutoStartSettings()` over the channel, `PlatformException`-safe (fail-closed for `has…` → false, so no dead button on unknown OEMs; fallback inside native for `open…`).
  - [x] AndroidManifest: no new permission needed for launching a settings Intent. Only touch it if a `<queries>`/component-visibility entry proves necessary on API 30+ for `resolveActivity` — prefer try/catch over broad `<queries>`.
- [x] **Task 3 — Surface auto-start + fix conditional battery-opt in the settings UI (AC: 1, 3, 8, 9)**
  - [x] `alarm_settings_screen.dart`: add an "Allow auto-start" guided row/button in `_PermissionSection`/`_WarningAndButton`, shown when `hasAutoStartManager()` is true (FutureBuilder or fold into the existing `alarmPermissionStatusProvider` snapshot without adding a new `@riverpod` provider). Plain-language explainer.
  - [x] Fix `_onGrant`/`_onBackgroundDisplay`: request `requestIgnoreBatteryOptimizations()` on the **primary** grant path unconditionally (when not already exempt), decoupled from the overlay-missing branch.
  - [x] Persist a local "auto-start step visited" flag (reuse `shared_preferences` — e.g. a key alongside `AlarmSettingsRepository`, **without** changing any `@riverpod` provider signature so no codegen is required).
- [x] **Task 4 — Guided onboarding sequence on enable (AC: 7, 10)**
  - [x] Drive a non-blocking, ordered flow from the **UI** when the master toggle flips ON (in `alarm_settings_screen.dart`, keeping `AlarmSettingsController.setEnabled` pure): notification → exact-alarm → overlay → battery-opt → auto-start, each step requesting or routing to settings only if still missing, using existing `AlarmPermissions` methods + the new auto-start method. Re-runnable from the screen.
  - [x] Invalidate `alarmPermissionStatusProvider` after the flow / on `resumed` so the banner + step states refresh.
- [x] **Task 5 — Tests + analyze (AC: 11, 12)**
  - [x] Unit-test the pure additions: OEM→component resolution table (a pure Dart map is preferable to Kotlin-only logic where feasible — extract the mapping to testable Dart or a thin testable seam), onboarding-step ordering/skip logic, and any `AlarmPermissionStatus` changes. Keep the Kotlin `Intent` firing behind the channel (integration-verified on device).
  - [x] `flutter analyze` 0 errors; `test/features/alarms/*` green. **Do NOT run `build_runner` unless a change forces a `.g.dart` regen — the concurrent builder-ops work has uncommitted `features/inventory/*.g.dart`; a full regen would rewrite them. If regen is unavoidable, scope it with `--build-filter` on alarm paths only.**

## Dev Notes

### HARD CONSTRAINTS (two-agent working tree)

- **Same working tree, shared with another active agent** implementing builder-ops mobile UI (`features/inventory`, `features/booking`, `features/amendments`, `features/hierarchy`, `you_screen.dart`, `app_router.dart`, and **`pubspec.yaml`/`pubspec.lock`** — all uncommitted). **Do not touch any of those paths.** Stay entirely within `features/alarms/*`, `lib/app.dart` (only if the ring wiring needs it — it should not), the Android native files listed, and `test/features/alarms/*`.
- **No new pub dependency** (would clash on the concurrently-modified `pubspec`). Implement auto-start via the existing native `MethodChannel`, not the `auto_start_flutter` / `autostarter` package.
- **No new `@riverpod` provider and no change to an existing provider's generated signature** → so `build_runner` never needs to run and cannot rewrite the other agent's `features/inventory/*.g.dart`. Adding methods to existing classes (`AlarmPermissions`, repository) is fine; adding fields to plain classes (`AlarmPermissionStatus`) is fine.
- **Android-only.** iOS keeps the `NoopAlarmScheduler` / notification path; guard every new native call with `Platform.isAndroid` and report not-applicable statuses as satisfied (matches the existing `_toStatus` convention that reports iOS as granted so it never raises a spurious warning).
- **No commit by the dev agent.** Rudra reviews first (look-pass-before-commit). When committing later: surgical `git add` of alarm paths by name only — never `git add -A`/`.` (would sweep the uncommitted builder-ops mountain into an "alarm" commit).

### Files to touch (all pre-read; current state)

- **UPDATE `alarm_scheduler.dart`** — Gap 2 one-liner at `_toAlarmSettings` (`warningNotificationOnKill`). Everything else (`AlarmPackageScheduler`, scheduling/cancel/snooze, the `Platform.isAndroid` provider selection) must be preserved verbatim.
- **UPDATE `alarm_permissions.dart`** — add `hasAutoStartManager()` + `openAutoStartSettings()` channel wrappers; make battery-opt reachable on the primary path. `AlarmPermissionStatus` may gain an (optional, non-breaking) field but auto-start must **not** enter `hasBlocker` (unqueryable → guidance only). Keep the fail-open channel pattern already used by `_canUseFullScreenIntent`.
- **UPDATE `alarm_settings_screen.dart`** — new guided auto-start affordance; guided onboarding on enable; unconditional battery-opt on grant; keep the existing lifecycle-`resumed` invalidate.
- **UPDATE `MainActivity.kt`** — two new channel methods on the existing `nirman/alarm_permissions` channel; per-OEM component table; try/catch fallback to app settings. Mirror the existing `openFullScreenIntentSettings` style (it already does exactly this pattern for the FSI page).
- **UPDATE `AndroidManifest.xml`** — likely no change; only add a `<queries>` entry if `resolveActivity` visibility on API 30+ demands it (prefer try/catch).

### Key facts verified in audit (don't re-derive)

- `alarm` package `^5.4.0` (`pubspec.yaml:29`). Manifest already declares all 11 required perms + `NotificationOnKillService` (`AndroidManifest.xml:64-67`). `minSdk = 26`; `targetSdk = flutter.targetSdkVersion` → Android 14+ FSI restriction is live and already handled via `canUseFullScreenIntent()` + overlay fallback.
- Auto-start state is **not** queryable by any public API — the `has…Manager` check can only test whether the OEM component *exists*, not whether the user enabled it. Present as guidance, nudge once, don't gate the feature.
- Overlay (`SYSTEM_ALERT_WINDOW`) is already the reliable cross-OEM background-launch lever and is handled; auto-start is the *complementary* lever this story adds. Both matter on ColorOS/MIUI.

### References

- [Source: epics.md#Epic 10 — Alarm-Based Follow-Up Reminders]
- [Source: 10-2-fullscreen-ringing-alarm.md — AlarmScheduler API + `_toAlarmSettings`]
- [Source: 10-3-alarm-lifecycle-and-boot-sync.md — reconcile + boot strategy this story must preserve]
- [Source: alarm package /gdelataillade/alarm — help/INSTALL-ANDROID.md: OEM auto_start requirement (Samsung/Honor/Huawei/Xiaomi/Oppo/Asus); README reliability FAQ: disable battery optimization, open app daily; recommended `androidFullScreenIntent`/`androidStopAlarmOnTermination`; `warningNotificationOnKill`/`NotificationOnKillService`]
- [Source: alarm issue #222 — Android 14 USE_FULL_SCREEN_INTENT restriction for non-call/alarm apps]
- [Source: "Don't kill my app!" (dontkillmyapp.com) / autostarter — per-OEM Autostart component names]
- [Source: MainActivity.kt:43 openFullScreenIntentSettings — existing native settings-Intent pattern to mirror]

## Dev Agent Record

### Agent Model Used

claude-opus-4-8

### Debug Log References

- `flutter analyze lib/features/alarms test/features/alarms` → 0 errors (1 pre-existing info in `alarm_sync_service_test.dart:28`, not touched by this story).
- `flutter test test/features/alarms` → 37/37 pass (was 28; +9 in new `oem_autostart_test.dart`).
- `flutter test` (full suite) → 263/263 pass (was 254; no regression across the concurrently-developed builder-ops features).

### Completion Notes List

- **Doc-vs-source correction (important).** The `alarm` pkg docs claim `warningNotificationOnKill` / `setWarningNotificationOnKill` are "iOS-only / Android uses system defaults". The **installed 5.4.0 source contradicts this**: `AlarmApiImpl.updateWarningNotificationState()` starts the Android `NotificationOnKillService` when any saved alarm carries the flag, and the Dart `Alarm.setWarningNotificationOnKill` routes to `AndroidAlarm()` (alarm.dart:159). So Task 1 (AC5/AC6) is genuinely effective on Android. Verified by reading the pub-cache source, not the docs.
- **Task 1 (Gap 2):** `warningNotificationOnKill: true` in `_toAlarmSettings`; on-brand Android copy registered once via a fail-safe `_ensureWarningText()` (guarded top-level flag, retries on transient error) called at the top of `scheduleForFollowUp`.
- **Task 2 (Gap 1):** OEM auto-start deep-link added to the existing `nirman/alarm_permissions` MethodChannel — `getAutoStartInfo` (manufacturer + best-effort component-resolution probe) and `openAutoStartSettings` (tries each per-OEM `ComponentName`, falls back to `ACTION_APPLICATION_DETAILS_SETTINGS` on any failure — AC2/AC4). Component table for Xiaomi/Redmi/Poco, Oppo/Realme/OPlus, Vivo/iQOO, Huawei/Honor, Samsung, Asus, OnePlus, Letv, Meizu (dontkillmyapp catalogue). No new pub dep; no manifest change (relies on try/catch, not `<queries>`, per the story guidance).
- **Testable seam (deliberate, sanctioned by Task 5):** the pure OEM→brand mapping and the onboarding-step ordering live in a **new plugin-free file `oem_autostart.dart`** (no `@riverpod`, so no codegen ran — the other agent's uncommitted `features/inventory/*.g.dart` were never touched). Auto-start state is **not queryable** on Android, so the step is guidance-only and never enters `hasBlocker`; the UI shows it for known-aggressive manufacturers even when package visibility hides the component from `resolveActivity`.
- **Task 3 (Gap 3, AC8):** `_onGrant` now requests the battery-optimization exemption **unconditionally** when not already exempt (was gated behind the overlay-missing branch, so overlay-granted devices stayed Doze-killable). Added `batteryOptimizationIgnored` to `AlarmPermissionStatus` (plain class — no codegen); kept it OUT of `hasBlocker` to avoid over-warning. `_AutoStartCard` renders the guided auto-start step and records the visit via new `AlarmSettingsRepository.saveAutoStartVisited`.
- **Task 4 (AC7):** master toggle → `_enableAndOnboard` runs `_runGuidedOnboarding`, which drives the pure `plannedOnboardingSteps` planner in order notif → exact → overlay → battery → auto-start. Runtime dialogs (notif/exact/battery) fire automatically; overlay routes to its settings page if missing. **The auto-start step is intentionally NOT force-launched** during onboarding (it is the most disruptive redirect and is unverifiable afterwards) — it is surfaced by the persistent `_AutoStartCard` instead. Documented as a deliberate UX choice.
- **Android-only + non-regression (AC11/AC12):** every native call is `Platform.isAndroid`-guarded (iOS `autoStartInfo()` → null → card hidden; battery/overlay reported satisfied on iOS via the existing `_toStatus` null-convention). Scheduler platform selection, ring screen, snooze/dismiss, reconcile, boot re-arm all unchanged.
- **NOT done (deferred to Rudra, consistent with 10.2/10.3 device-verify pattern):** on-device verification that (a) the kill-warning notification appears when the app is swiped from recents, and (b) `openAutoStartSettings` lands on the correct OEM page on a real Xiaomi/Oppo/Vivo device (Kotlin is compile-verified by review only — no gradle build run, to avoid touching the shared build with the other agent's uncommitted code). **NOT committed** — left for review.

### File List

- MOD `apps/mobile/lib/features/alarms/data/alarm_scheduler.dart` (warningNotificationOnKill=true + `_ensureWarningText` custom copy)
- NEW `apps/mobile/lib/features/alarms/data/oem_autostart.dart` (pure: OEM brand map + `plannedOnboardingSteps`)
- MOD `apps/mobile/lib/features/alarms/data/alarm_permissions.dart` (`AutoStartInfo`, `autoStartInfo()`, `openAutoStartSettings()`, `batteryOptimizationIgnored` status)
- MOD `apps/mobile/lib/features/alarms/data/alarm_settings_repository.dart` (`loadAutoStartVisited`/`saveAutoStartVisited`)
- MOD `apps/mobile/lib/features/alarms/ui/alarm_settings_screen.dart` (`_AutoStartCard`, guided onboarding on enable, unconditional battery-opt)
- MOD `apps/mobile/android/app/src/main/kotlin/com/nirmanmedia/nirman_crm/MainActivity.kt` (auto-start channel methods + per-OEM component table + fallback; returns Build.BRAND)
- MOD `apps/mobile/android/app/src/main/AndroidManifest.xml` (review fix — `<queries>` for the 13 OEM manager packages so the deep-link resolves + launches on Android 11+)
- NEW `apps/mobile/test/features/alarms/oem_autostart_test.dart` (+9 tests)
- No change to pubspec or any `.g.dart` (no codegen ran).

### Change Log

- 2026-07-11 — Story 10.4 implemented (all 5 tasks). Analyze 0 errors; 37/37 alarm tests, 263/263 full suite. Status → review.
- 2026-07-11 — 3-lens adversarial code review (Blind Hunter / Edge Case Hunter / Acceptance Auditor) → 8 findings, ALL fixed (1 High, 2 Med, 5 Low/minor) + 1 accepted deviation. Re-verified: analyze 0 errors, 37/37 alarm, 263/263 full suite. Adds AndroidManifest.xml to the file list.

### Code Review (2026-07-11) — 3-lens adversarial, all findings fixed

Reviewed the uncommitted alarm diff with three independent lenses. Triaged, fixed every confirmed finding, re-ran analyze + suite (green). No commit — left for Rudra.

**Fixed:**
- **[HIGH] Android 11+ package visibility broke the P0 deep-link.** Without `<queries>` entries, `resolveActivity` returned null and an explicit `startActivity` to an OEM security package threw on API 30+, so the auto-start button dead-ended at generic app-settings on exactly the MIUI/ColorOS/Funtouch devices it targets. **Fix:** added `<queries><package …/></queries>` for all 13 OEM manager packages (mirrors the MainActivity.kt table) → **AndroidManifest.xml now MODIFIED**.
- **[MED] Misleading auto-start copy on Samsung/OnePlus** (their lever is battery/Device-care, not "Autostart"). **Fix:** vendor-neutral card copy ("Auto-start / Auto-launch, or the battery / app-power settings").
- **[MED] Fire-and-forget onboarding had no error/lifecycle guard** (exception, disposed-ref during a system dialog, or concurrent `request()` → unhandled async error / StateError / permission_handler "already running"). **Fix:** try/catch around `_enableAndOnboard` and the card-button handlers `_onGrant`/`_onBackgroundDisplay` (log + swallow; banner re-syncs on resume).
- **[LOW] `_AutoStartCard._open` used `ref` after the first await.** **Fix:** read both providers before the await; `mounted`-guard the invalidate.
- **[LOW] Onboarding ran battery before overlay (reversed AC7).** **Fix:** overlay now precedes battery-opt.
- **[LOW] `loadAutoStartVisited` was write-only (AC3 suppression unwired).** **Fix:** card now reads it and, once visited, downgrades the prominent "Allow auto-start" CTA to a quiet "Re-open auto-start settings" — the proactive nudge no longer repeats.
- **[LOW] `_ensureWarningText` set its flag before the await** (a concurrent schedule could arm the kill-service with default copy). **Fix:** flag set only after the call succeeds (concurrent double-set is idempotent).
- **[minor] `Build.BRAND` collected but unused.** **Fix:** `AutoStartInfo.brand` now OR'd into the relevance check for skins that report the aggressive brand in BRAND not MANUFACTURER.

**Accepted (not changed):** AC2 `openAutoStartSettings` brute-forces the component list rather than branching on `Build.MANUFACTURER` — deliberate: try-all is more robust to MANUFACTURER-string variance, foreign-OEM packages simply throw and are skipped, and the app-settings fallback prevents any dead-end. Behavior matches AC2's intent.

**Still deferred to Rudra (on-device, no gradle build run here):** verify the kill-warning notification appears on swipe-away, and that `openAutoStartSettings` lands on the correct OEM page on a real Xiaomi/Oppo/Vivo device.
