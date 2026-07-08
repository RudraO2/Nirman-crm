// Story 10.3 — reconcile() decision logic. Pure: a fake scheduler records the
// cancel/schedule calls, fake settings + fake lead source drive the inputs. No
// `alarm` plugin and no Supabase needed (the snooze-preserving cancel itself
// lives in AlarmPackageScheduler.cancelScheduledAlarms and is verified on-device;
// here we assert reconcile routes to that selective cancel, never the bulk one).

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/alarms/data/alarm_scheduler.dart';
import 'package:nirman_crm/features/alarms/data/alarm_sync_service.dart';
import 'package:nirman_crm/features/alarms/data/models/alarm_settings.dart';
import 'package:nirman_crm/features/alarms/data/models/follow_up_alarm.dart';
import 'package:nirman_crm/features/leads/data/models/lead_model.dart';

class _ScheduledCall {
  _ScheduledCall(this.leadId, this.leadName, this.followUpAt, this.reason);
  final String leadId;
  final String leadName;
  final DateTime followUpAt;
  final String reason;
}

/// Records every scheduler interaction. scheduleForFollowUp returns one "alarm"
/// per offset so reconcile's aggregate count is observable. [ops] captures the
/// call order so we can assert cancel-then-schedule sequencing.
class FakeScheduler implements AlarmScheduler {
  final List<String> cancelAllReasons = [];
  final List<String> cancelScheduledReasons = [];
  final List<_ScheduledCall> scheduled = [];
  final List<String> ops = [];

  @override
  Future<void> cancelAllAlarms({required String reason}) async {
    cancelAllReasons.add(reason);
    ops.add('cancel_all');
  }

  @override
  Future<void> cancelScheduledAlarms({required String reason}) async {
    cancelScheduledReasons.add(reason);
    ops.add('cancel_scheduled');
  }

  @override
  Future<int> scheduleForFollowUp({
    required String leadId,
    required String leadName,
    required DateTime followUpAt,
    required AlarmSettings settings,
    required String reason,
  }) async {
    scheduled.add(_ScheduledCall(leadId, leadName, followUpAt, reason));
    ops.add('schedule:$leadId');
    return settings.offsetsMinutes.length;
  }

  @override
  Future<void> dismiss(int alarmId, {FollowUpAlarmPayload? payload}) async {}

  @override
  Future<void> snooze(int alarmId, FollowUpAlarmPayload payload) async {}
}

LeadListItem _lead(String id, {DateTime? followUp, String? name}) => LeadListItem(
      id: id,
      status: 'active',
      name: name,
      nextFollowupAt: followUp,
      isIncomplete: false,
      createdAt: DateTime(2026, 6, 1),
      urgencyScore: 0,
    );

AlarmSyncService _service(
  FakeScheduler scheduler, {
  required AlarmSettings settings,
  required List<LeadListItem> leads,
}) =>
    AlarmSyncService(
      scheduler: scheduler,
      loadSettings: () async => settings,
      loadLeads: () async => leads,
    );

void main() {
  final future = DateTime.now().add(const Duration(hours: 2));
  const enabled = AlarmSettings(enabled: true, offsetsMinutes: [10, 30]);

  group('reconcile — disabled', () {
    test('cancels all and schedules nothing', () async {
      final s = FakeScheduler();
      await _service(
        s,
        settings: const AlarmSettings(enabled: false, offsetsMinutes: [10]),
        leads: [_lead('a', followUp: future)],
      ).reconcile(reason: 'app_open');

      expect(s.cancelAllReasons, ['reconcile_disabled:app_open']);
      expect(s.cancelScheduledReasons, isEmpty);
      expect(s.scheduled, isEmpty);
    });
  });

  group('reconcile — enabled', () {
    test('selective-cancels then schedules each lead with a follow-up', () async {
      final s = FakeScheduler();
      await _service(
        s,
        settings: enabled,
        leads: [
          _lead('a', followUp: future, name: 'Asha'),
          _lead('b', followUp: future, name: 'Bina'),
        ],
      ).reconcile(reason: 'leads_changed');

      // Selective cancel (preserves snooze/ringing) — never the bulk cancel.
      expect(s.cancelScheduledReasons, ['reconcile:leads_changed']);
      expect(s.cancelAllReasons, isEmpty);
      expect(s.scheduled.map((c) => c.leadId), ['a', 'b']);
    });

    test('skips leads with no next follow-up (null)', () async {
      final s = FakeScheduler();
      await _service(
        s,
        settings: enabled,
        leads: [
          _lead('a', followUp: future),
          _lead('b', followUp: null), // completed/no follow-up → no alarm
        ],
      ).reconcile(reason: 'app_open');

      expect(s.scheduled.map((c) => c.leadId), ['a']);
    });

    test('falls back to a placeholder name when lead name is blank', () async {
      final s = FakeScheduler();
      await _service(
        s,
        settings: enabled,
        leads: [_lead('a', followUp: future, name: '  ')],
      ).reconcile(reason: 'app_open');

      expect(s.scheduled.single.leadName, 'your lead');
    });

    test('a removed lead gets no alarm on the next reconcile', () async {
      final s = FakeScheduler();
      // Second reconcile only sees lead 'a' (lead 'b' archived/reassigned away):
      // cancel-then-rebuild means 'b' simply is not re-scheduled.
      await _service(s, settings: enabled, leads: [_lead('a', followUp: future)])
          .reconcile(reason: 'leads_changed');

      expect(s.cancelScheduledReasons, hasLength(1));
      expect(s.scheduled.map((c) => c.leadId), ['a']);
    });

    test('passes the caller-loaded list when leads are supplied (no refetch)', () async {
      final s = FakeScheduler();
      // loadLeads throws to prove the supplied list is used instead.
      final svc = AlarmSyncService(
        scheduler: s,
        loadSettings: () async => enabled,
        loadLeads: () async => throw StateError('should not fetch'),
      );
      await svc.reconcile(reason: 'leads_changed', leads: [_lead('a', followUp: future)]);

      expect(s.scheduled.map((c) => c.leadId), ['a']);
    });

    test('cancels before it schedules (no stale alarm survives)', () async {
      final s = FakeScheduler();
      await _service(s, settings: enabled, leads: [_lead('a', followUp: future)])
          .reconcile(reason: 'app_open');

      expect(s.ops, ['cancel_scheduled', 'schedule:a']);
    });

    test('threads the lifecycle reason into the per-alarm schedule (AC6)', () async {
      final s = FakeScheduler();
      await _service(s, settings: enabled, leads: [_lead('a', followUp: future)])
          .reconcile(reason: 'followup_set');

      expect(s.scheduled.single.reason, 'followup_set');
    });
  });

  group('reconcile — concurrency (M1 guard)', () {
    test('overlapping reconciles run serially, never interleaved', () async {
      final s = FakeScheduler();
      final svc = _service(s, settings: enabled, leads: [_lead('a', followUp: future)]);

      // Fire two without awaiting the first — the guard must serialize them so
      // ops are two full cancel→schedule cycles, not cancel,cancel,schedule,schedule.
      final f1 = svc.reconcile(reason: 'leads_changed');
      final f2 = svc.reconcile(reason: 'app_open');
      await Future.wait([f1, f2]);

      expect(s.ops, [
        'cancel_scheduled', 'schedule:a',
        'cancel_scheduled', 'schedule:a',
      ]);
    });
  });
}
