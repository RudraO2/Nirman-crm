// Story 10.1 — OS permission wrapper for follow-up alarms.
//
// Android needs POST_NOTIFICATIONS (13+) and SCHEDULE_EXACT_ALARM (12+) for the
// 10.2 exact full-screen alarm. iOS has no exact-alarm concept and degrades to a
// time-sensitive notification, so only notification permission applies there.
//
// USE_FULL_SCREEN_INTENT is manifest-declared, but on Android 14+ (API 34) it is
// NOT auto-granted to non-call/alarm apps: a backgrounded alarm then degrades to
// a heads-up notification (sound only, no full-screen ring). permission_handler
// has no API for this special access, so a native MethodChannel (MainActivity.kt)
// checks NotificationManager.canUseFullScreenIntent() and opens the dedicated
// settings page (ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'alarm_permissions.g.dart';

/// Snapshot of the alarm-relevant OS permissions for the warning banner (AC5).
class AlarmPermissionStatus {
  final bool notificationGranted;

  /// Android-only. On iOS this is reported as granted (not applicable) so it
  /// never raises a spurious warning.
  final bool exactAlarmGranted;

  /// Android 14+ full-screen-intent special access. Stock-Android lever for the
  /// full-screen takeover. OEM skins (ColorOS/MIUI) often lack the settings page,
  /// so [systemAlertWindowGranted] is the reliable lever there.
  /// Reported granted on iOS / pre-14 so it never raises a spurious warning.
  final bool fullScreenIntentGranted;

  /// "Display over other apps" (overlay). On OEM skins, granting this lifts the
  /// background-activity-launch block so the ring screen shows over other apps.
  /// Reported granted on iOS so it never raises a spurious warning.
  final bool systemAlertWindowGranted;

  /// True when the user must visit system settings (a permission is
  /// permanently denied), so the UI offers an "Open settings" action.
  final bool needsSystemSettings;

  const AlarmPermissionStatus({
    required this.notificationGranted,
    required this.exactAlarmGranted,
    required this.fullScreenIntentGranted,
    required this.systemAlertWindowGranted,
    required this.needsSystemSettings,
  });

  /// The alarm can take over the screen from the background if EITHER the
  /// stock full-screen-intent access OR the OEM overlay permission is granted.
  bool get backgroundDisplayGranted =>
      fullScreenIntentGranted || systemAlertWindowGranted;

  /// AC5: any missing permission → show the non-blocking warning.
  bool get hasBlocker =>
      !notificationGranted || !exactAlarmGranted || !backgroundDisplayGranted;
}

class AlarmPermissions {
  const AlarmPermissions();

  static const MethodChannel _channel = MethodChannel('nirman/alarm_permissions');

  bool get _isAndroid => Platform.isAndroid;

  Future<bool> _canUseFullScreenIntent() async {
    if (!_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('canUseFullScreenIntent') ?? true;
    } on PlatformException {
      return true; // fail open — don't block the feature on a channel error.
    }
  }

  Future<AlarmPermissionStatus> status() async {
    final notif = await Permission.notification.status;
    final exact =
        _isAndroid ? await Permission.scheduleExactAlarm.status : null;
    final overlay =
        _isAndroid ? await Permission.systemAlertWindow.status : null;
    final fsi = await _canUseFullScreenIntent();
    return _toStatus(notif, exact, overlay, fsi);
  }

  /// Requests the required permissions and returns the resulting status.
  /// Full-screen-intent has no request dialog — if it is still missing after the
  /// runtime grants, the caller should route to [openFullScreenIntentSettings]
  /// or [requestOverlay] (the reliable OEM lever).
  Future<AlarmPermissionStatus> request() async {
    final notif = await Permission.notification.request();
    final exact =
        _isAndroid ? await Permission.scheduleExactAlarm.request() : null;
    final overlay =
        _isAndroid ? await Permission.systemAlertWindow.status : null;
    final fsi = await _canUseFullScreenIntent();
    return _toStatus(notif, exact, overlay, fsi);
  }

  /// Opens the "Display over other apps" page for this app (reliable across OEM
  /// skins) and returns the resulting status. This is the lever that makes the
  /// full-screen alarm appear over other apps on ColorOS/MIUI/etc.
  Future<AlarmPermissionStatus> requestOverlay() async {
    if (_isAndroid) await Permission.systemAlertWindow.request();
    return status();
  }

  /// Asks the OS to exempt the app from battery optimization (improves alarm
  /// reliability on aggressive OEMs — see the alarm package FAQ).
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (_isAndroid) await Permission.ignoreBatteryOptimizations.request();
  }

  Future<void> openSystemSettings() => openAppSettings();

  /// Opens the Android 14+ "Full screen intents" special-access page for this app.
  Future<void> openFullScreenIntentSettings() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openFullScreenIntentSettings');
    } on PlatformException {
      await openAppSettings();
    }
  }

  AlarmPermissionStatus _toStatus(PermissionStatus notif,
      PermissionStatus? exact, PermissionStatus? overlay, bool fsiGranted) {
    final notifOk = notif.isGranted;
    // null → iOS (not applicable) → treat as satisfied.
    final exactOk = exact == null || exact.isGranted;
    final overlayOk = overlay == null || overlay.isGranted;
    final needsSettings =
        notif.isPermanentlyDenied || (exact?.isPermanentlyDenied ?? false);
    return AlarmPermissionStatus(
      notificationGranted: notifOk,
      exactAlarmGranted: exactOk,
      fullScreenIntentGranted: fsiGranted,
      systemAlertWindowGranted: overlayOk,
      needsSystemSettings: needsSettings,
    );
  }
}

@riverpod
AlarmPermissions alarmPermissions(AlarmPermissionsRef ref) =>
    const AlarmPermissions();

/// Current permission snapshot for the warning banner. Invalidated after a
/// grant request so the banner refreshes.
@riverpod
Future<AlarmPermissionStatus> alarmPermissionStatus(
    AlarmPermissionStatusRef ref) {
  return ref.watch(alarmPermissionsProvider).status();
}
