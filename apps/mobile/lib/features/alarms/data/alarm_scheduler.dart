// Story 10.1/10.2 — Alarm scheduler.
//
// Story 10.1 shipped this as a logged no-op seam (cancel-on-disable only).
// Story 10.2 adds the real Android implementation over the `alarm` package:
// schedules an exact, full-screen, ring-until-acted alarm per enabled offset for
// a follow-up, supports snooze (5 min) and dismiss, and a real cancel-all.
//
// Platform: Android only this story. iOS keeps the no-op (a time-sensitive
// critical-notification path is a documented, deferred follow-up — see the
// story file). Selection happens in [alarmScheduler] below.
//
// The `alarm` package also exports a type named `AlarmSettings`, which clashes
// with our device-settings model of the same name, so it is imported aliased.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:alarm/alarm.dart' as alarm;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'alarm_planning.dart';
import 'models/alarm_settings.dart';
import 'models/follow_up_alarm.dart';

part 'alarm_scheduler.g.dart';

abstract class AlarmScheduler {
  /// Cancel every pending follow-up alarm on the device (AC3 of 10.1) —
  /// used by the master-toggle-off path.
  Future<void> cancelAllAlarms({required String reason});

  /// Cancel only future, non-snooze follow-up alarms, preserving any alarm that
  /// is currently ringing or is a pending snooze re-ring. Used by the Story 10.3
  /// reconcile so a cancel-then-rebuild never silences an alarm the user is
  /// actively dealing with.
  Future<void> cancelScheduledAlarms({required String reason});

  /// Schedule one alarm per enabled offset for [followUpAt]. No-op when alarms
  /// are disabled or no offset resolves to a future time. Returns the count
  /// actually scheduled. [reason] is the lifecycle event that triggered this
  /// (e.g. 'followup_set', 'app_open') and is included in the per-alarm log (AC6).
  Future<int> scheduleForFollowUp({
    required String leadId,
    required String leadName,
    required DateTime followUpAt,
    required AlarmSettings settings,
    required String reason,
  });

  /// Stop a ringing alarm (Dismiss action).
  Future<void> dismiss(int alarmId, {FollowUpAlarmPayload? payload});

  /// Stop the ringing alarm and re-ring [kAlarmSnoozeInterval] later (Snooze).
  Future<void> snooze(int alarmId, FollowUpAlarmPayload payload);
}

void _log(Map<String, Object?> fields) {
  final body = fields.entries
      .map((e) => "'${e.key}':${_enc(e.value)}")
      .join(',');
  developer.log('{$body}', name: 'alarms');
}

String _enc(Object? v) =>
    v is num || v is bool ? '$v' : "'${v.toString().replaceAll("'", r"\'")}'";

/// Story 10.4 — register on-brand copy for the app-killed warning notification
/// (Android NotificationOnKillService), once. The `alarm` package default is the
/// generic "Your alarms may not ring"; this makes it specific to follow-ups.
/// Idempotent + fail-safe: a transient failure leaves it unset so a later
/// schedule retries. Only the strings are set here — the service is armed by any
/// scheduled alarm carrying `warningNotificationOnKill: true`.
bool _warningTextConfigured = false;

Future<void> _ensureWarningText() async {
  if (_warningTextConfigured) return;
  try {
    await alarm.Alarm.setWarningNotificationOnKill(
      'Follow-up alarms may not ring',
      'Nirman CRM was closed from recents. Reopen it so your follow-up alarms '
          'keep ringing on time.',
    );
    // Only mark done AFTER the call succeeds. A concurrent first-time schedule
    // may set the (identical) text twice — harmless and idempotent — but the
    // custom copy is never skipped while still in flight, and a transient
    // failure simply retries on the next schedule.
    _warningTextConfigured = true;
  } catch (e) {
    _log({'event': 'alarm_error', 'op': 'set_kill_warning_text', 'error': '$e'});
  }
}

/// Default until 10.2 wiring / on iOS: logs intent without touching the OS.
class NoopAlarmScheduler implements AlarmScheduler {
  const NoopAlarmScheduler();

  @override
  Future<void> cancelAllAlarms({required String reason}) async {
    _log({'event': 'alarms_cancel_all', 'reason': reason, 'impl': 'noop'});
  }

  @override
  Future<void> cancelScheduledAlarms({required String reason}) async {
    _log({'event': 'alarms_cancel_scheduled', 'reason': reason, 'impl': 'noop'});
  }

  @override
  Future<int> scheduleForFollowUp({
    required String leadId,
    required String leadName,
    required DateTime followUpAt,
    required AlarmSettings settings,
    required String reason,
  }) async {
    _log({
      'event': 'alarm_schedule_skipped',
      'cause': 'noop_platform',
      'reason': reason,
      'lead_id': leadId,
      'followup_at': followUpAt.toIso8601String(),
    });
    return 0;
  }

  @override
  Future<void> dismiss(int alarmId, {FollowUpAlarmPayload? payload}) async {
    _log({'event': 'alarm_dismiss', 'alarm_id': alarmId, 'impl': 'noop'});
  }

  @override
  Future<void> snooze(int alarmId, FollowUpAlarmPayload payload) async {
    _log({'event': 'alarm_snooze', 'alarm_id': alarmId, 'impl': 'noop'});
  }
}

/// Android implementation backed by the `alarm` package.
class AlarmPackageScheduler implements AlarmScheduler {
  const AlarmPackageScheduler();

  @override
  Future<void> cancelAllAlarms({required String reason}) async {
    try {
      final pending = await alarm.Alarm.getAlarms();
      for (final a in pending) {
        await alarm.Alarm.stop(a.id);
      }
      _log({
        'event': 'alarms_cancel_all',
        'reason': reason,
        'count': pending.length,
        'impl': 'alarm_pkg',
      });
    } catch (e) {
      _log({'event': 'alarm_error', 'op': 'cancel_all', 'error': '$e'});
    }
  }

  @override
  Future<void> cancelScheduledAlarms({required String reason}) async {
    try {
      final now = DateTime.now();
      final pending = await alarm.Alarm.getAlarms();
      var cancelled = 0;
      for (final a in pending) {
        final payload = FollowUpAlarmPayload.tryDecode(a.payload);
        // Preserve a pending snooze re-ring.
        if (payload?.isSnooze == true) continue;
        // Preserve an alarm that is at/just-past its fire time (ringing now).
        if (!a.dateTime.isAfter(now)) continue;
        await alarm.Alarm.stop(a.id);
        cancelled++;
        _log({
          'event': 'alarm_cancelled',
          'reason': reason,
          'lead_id': payload?.leadId,
          'followup_at': payload?.followUpAt.toIso8601String(),
          'offset_minutes': payload?.offsetMinutes,
          'alarm_id': a.id,
        });
      }
      _log({
        'event': 'alarms_cancel_scheduled',
        'reason': reason,
        'count': cancelled,
        'impl': 'alarm_pkg',
      });
    } catch (e) {
      _log({'event': 'alarm_error', 'op': 'cancel_scheduled', 'error': '$e'});
    }
  }

  @override
  Future<int> scheduleForFollowUp({
    required String leadId,
    required String leadName,
    required DateTime followUpAt,
    required AlarmSettings settings,
    required String reason,
  }) async {
    if (!settings.enabled) {
      _log({
        'event': 'alarm_schedule_skipped',
        'cause': 'disabled',
        'reason': reason,
        'lead_id': leadId,
        'followup_at': followUpAt.toIso8601String(),
      });
      return 0;
    }

    // Story 10.4 — ensure the app-killed warning carries follow-up-specific copy
    // before the first alarm arms the NotificationOnKillService.
    await _ensureWarningText();

    final planned = planFollowUpAlarms(
      leadId: leadId,
      leadName: leadName,
      followUpAt: followUpAt,
      offsetsMinutes: settings.offsetsMinutes,
      now: DateTime.now(),
    );

    var scheduled = 0;
    for (final p in planned) {
      try {
        await alarm.Alarm.set(
          alarmSettings: _toAlarmSettings(p.id, p.fireTime, p.payload),
        );
        scheduled++;
        _log({
          'event': 'alarm_scheduled',
          'reason': reason,
          'lead_id': leadId,
          'followup_at': followUpAt.toIso8601String(),
          'offset_minutes': p.payload.offsetMinutes,
          'alarm_id': p.id,
          'fire_at': p.fireTime.toIso8601String(),
        });
      } catch (e) {
        _log({
          'event': 'alarm_error',
          'op': 'schedule',
          'lead_id': leadId,
          'alarm_id': p.id,
          'error': '$e',
        });
      }
    }
    return scheduled;
  }

  @override
  Future<void> dismiss(int alarmId, {FollowUpAlarmPayload? payload}) async {
    try {
      await alarm.Alarm.stop(alarmId);
      _log({
        'event': 'alarm_dismiss',
        'alarm_id': alarmId,
        'lead_id': payload?.leadId,
        'offset_minutes': payload?.offsetMinutes,
      });
    } catch (e) {
      _log({
        'event': 'alarm_error',
        'op': 'dismiss',
        'alarm_id': alarmId,
        'error': '$e',
      });
    }
  }

  @override
  Future<void> snooze(int alarmId, FollowUpAlarmPayload payload) async {
    final snoozed = payload.asSnooze();
    final fireTime = DateTime.now().add(kAlarmSnoozeInterval);
    final snoozeId = alarmIdFor(
      payload.leadId,
      payload.followUpAt,
      payload.offsetMinutes,
      snooze: true,
    );
    try {
      await alarm.Alarm.stop(alarmId);
      await alarm.Alarm.set(
        alarmSettings: _toAlarmSettings(snoozeId, fireTime, snoozed),
      );
      _log({
        'event': 'alarm_snooze',
        'alarm_id': alarmId,
        'snooze_alarm_id': snoozeId,
        'lead_id': payload.leadId,
        'fire_at': fireTime.toIso8601String(),
      });
    } catch (e) {
      _log({
        'event': 'alarm_error',
        'op': 'snooze',
        'alarm_id': alarmId,
        'error': '$e',
      });
    }
  }

  alarm.AlarmSettings _toAlarmSettings(
    int id,
    DateTime fireTime,
    FollowUpAlarmPayload payload,
  ) {
    return alarm.AlarmSettings(
      id: id,
      dateTime: fireTime,
      // null → device default alarm sound (no bundled/licensed asset needed).
      assetAudioPath: null,
      loopAudio: true,
      vibrate: true,
      // Story 10.4 — on Android, `alarm` 5.4.0 DOES honour this flag (contrary to
      // the pkg docs): AlarmApiImpl.updateWarningNotificationState() starts the
      // manifest-declared NotificationOnKillService when any saved alarm has it
      // set, so the user is warned that swiping the app away (which cancels
      // alarms on aggressive OEMs) may stop their follow-up alarm. Custom text is
      // set via Alarm.setWarningNotificationOnKill in _ensureWarningText().
      warningNotificationOnKill: true,
      androidFullScreenIntent: true,
      androidStopAlarmOnTermination: false,
      volumeSettings: alarm.VolumeSettings.fade(
        volume: 0.9,
        fadeDuration: const Duration(seconds: 3),
        volumeEnforced: true,
      ),
      notificationSettings: alarm.NotificationSettings(
        // No customer name here (audit medium): the title is lockscreen-visible
        // and persisted plaintext by the alarm plugin. The name shows only on
        // the in-app ring screen (masked at the sync seam).
        title: 'Follow-up reminder',
        body: payload.isSnooze
            ? 'Snoozed follow-up reminder'
            : 'Your follow-up is coming up',
        stopButton: 'Dismiss',
      ),
      payload: payload.encode(),
    );
  }
}

/// Android → real scheduler; everything else → logged no-op (iOS deferred).
@riverpod
AlarmScheduler alarmScheduler(AlarmSchedulerRef ref) =>
    Platform.isAndroid ? const AlarmPackageScheduler() : const NoopAlarmScheduler();
