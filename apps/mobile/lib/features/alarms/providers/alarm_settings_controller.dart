// Story 10.1 — Alarm settings controller.
//
// Loads device-local AlarmSettings and applies mutations (master toggle, offset
// add/remove). On the enabled→disabled transition it cancels all scheduled
// alarms (AC3) via the AlarmScheduler seam (10.2 swaps in the real canceller).

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/alarm_scheduler.dart';
import '../data/alarm_settings_repository.dart';
import '../data/alarm_sync_service.dart';
import '../data/models/alarm_settings.dart';

part 'alarm_settings_controller.g.dart';

@riverpod
class AlarmSettingsController extends _$AlarmSettingsController {
  @override
  Future<AlarmSettings> build() {
    return ref.watch(alarmSettingsRepositoryProvider).load();
  }

  AlarmSettings get _current => state.valueOrNull ?? AlarmSettings.initial;

  Future<void> _persist(AlarmSettings next) async {
    state = AsyncData(next);
    await ref.read(alarmSettingsRepositoryProvider).save(next);
  }

  /// Flip the master enable toggle. Turning it OFF cancels all pending alarms
  /// (AC3) and stops new scheduling.
  Future<void> setEnabled(bool enabled) async {
    final prev = _current;
    if (prev.enabled == enabled) return;
    await _persist(prev.copyWith(enabled: enabled));
    if (!enabled) {
      await ref
          .read(alarmSchedulerProvider)
          .cancelAllAlarms(reason: 'master_toggle_off');
    } else {
      // Story 10.3 (Task 5) — on (re)enable, rebuild alarms for the user's
      // existing pending follow-ups (no lead mutation fires the home listener).
      await ref
          .read(alarmSyncServiceProvider)
          .reconcile(reason: 'alarms_enabled');
    }
  }

  /// Enable/disable a single lead-time offset (preset or custom).
  Future<void> setOffset(int minutes, bool on) async {
    final next = _current.withOffset(minutes, on);
    if (next == _current) return;
    await _persist(next);
    // Story 10.3 (Task 5) — offsets define how many alarms each follow-up gets,
    // so rebuild against the new offset set. Skipped while disabled (reconcile
    // cancels-only in that case, which is correct).
    if (next.enabled) {
      await ref
          .read(alarmSyncServiceProvider)
          .reconcile(reason: 'offsets_changed');
    }
  }

  /// Add a custom offset (minutes). No-op if non-positive / out of range /
  /// already present.
  Future<void> addCustomOffset(int minutes) async {
    if (minutes <= 0 || minutes > kMaxAlarmOffsetMinutes) return;
    await setOffset(minutes, true);
  }
}
