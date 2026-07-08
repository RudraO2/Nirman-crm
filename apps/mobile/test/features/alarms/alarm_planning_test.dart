// Story 10.2 — pure alarm-planning logic tests (fire-time, past-skip, ids,
// payload round-trip, offset label). No plugin needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/alarms/data/alarm_planning.dart';
import 'package:nirman_crm/features/alarms/data/models/follow_up_alarm.dart';

void main() {
  final followUp = DateTime(2026, 6, 1, 10, 0); // 10:00
  final now = DateTime(2026, 6, 1, 9, 0); // 1h before

  group('planFollowUpAlarms', () {
    test('one alarm per future offset, firing offset-minutes before', () {
      final plan = planFollowUpAlarms(
        leadId: 'lead-1',
        leadName: 'Asha',
        followUpAt: followUp,
        offsetsMinutes: [10, 30],
        now: now,
      );
      expect(plan, hasLength(2));
      final byOffset = {for (final p in plan) p.payload.offsetMinutes: p};
      expect(byOffset[30]!.fireTime, DateTime(2026, 6, 1, 9, 30));
      expect(byOffset[10]!.fireTime, DateTime(2026, 6, 1, 9, 50));
    });

    test('skips offsets whose fire time is already in the past (AC)', () {
      // now = 9:00. offset 90 → fire 8:30 (past) skipped; offset 30 → 9:30 kept.
      final plan = planFollowUpAlarms(
        leadId: 'lead-1',
        leadName: 'Asha',
        followUpAt: followUp,
        offsetsMinutes: [90, 30],
        now: now,
      );
      expect(plan.map((p) => p.payload.offsetMinutes), [30]);
    });

    test('empty offsets → no alarms', () {
      expect(
        planFollowUpAlarms(
          leadId: 'l',
          leadName: 'n',
          followUpAt: followUp,
          offsetsMinutes: const [],
          now: now,
        ),
        isEmpty,
      );
    });

    test('every offset past → empty (no spurious ring)', () {
      final plan = planFollowUpAlarms(
        leadId: 'l',
        leadName: 'n',
        followUpAt: followUp,
        offsetsMinutes: [10, 30],
        now: DateTime(2026, 6, 1, 9, 55), // both fire times already passed
      );
      expect(plan, isEmpty);
    });

    test('payload carries lead + follow-up time for the ring screen', () {
      final p = planFollowUpAlarms(
        leadId: 'lead-7',
        leadName: 'Ravi',
        followUpAt: followUp,
        offsetsMinutes: [10],
        now: now,
      ).single;
      expect(p.payload.leadId, 'lead-7');
      expect(p.payload.leadName, 'Ravi');
      expect(p.payload.followUpAt, followUp);
      expect(p.payload.isSnooze, isFalse);
    });
  });

  group('alarmIdFor', () {
    test('is deterministic, positive, and 31-bit', () {
      final a = alarmIdFor('lead-1', followUp, 10);
      final b = alarmIdFor('lead-1', followUp, 10);
      expect(a, b);
      expect(a, greaterThanOrEqualTo(0));
      expect(a, lessThanOrEqualTo(0x7fffffff));
    });

    test('differs by lead, follow-up time, and offset', () {
      final base = alarmIdFor('lead-1', followUp, 10);
      expect(alarmIdFor('lead-2', followUp, 10), isNot(base));
      expect(alarmIdFor('lead-1', followUp, 30), isNot(base));
      expect(
        alarmIdFor('lead-1', followUp.add(const Duration(minutes: 1)), 10),
        isNot(base),
      );
    });

    test('snooze id never collides with the offset-0 alarm id', () {
      expect(
        alarmIdFor('lead-1', followUp, 0, snooze: true),
        isNot(alarmIdFor('lead-1', followUp, 0)),
      );
    });
  });

  group('FollowUpAlarmPayload', () {
    test('encode/decode round-trips', () {
      final payload = FollowUpAlarmPayload(
        leadId: 'lead-1',
        leadName: 'Asha Rao',
        followUpAt: followUp,
        offsetMinutes: 10,
      );
      expect(FollowUpAlarmPayload.tryDecode(payload.encode()), payload);
    });

    test('asSnooze flags snooze and keeps offset, lead + time', () {
      final snoozed = FollowUpAlarmPayload(
        leadId: 'lead-1',
        leadName: 'Asha',
        followUpAt: followUp,
        offsetMinutes: 10,
      ).asSnooze();
      expect(snoozed.isSnooze, isTrue);
      // Offset is retained (not zeroed) so per-offset snooze ids stay distinct.
      expect(snoozed.offsetMinutes, 10);
      expect(snoozed.leadId, 'lead-1');
      expect(snoozed.followUpAt, followUp);
    });

    test('snooze ids of two offsets on the same follow-up do not collide', () {
      // Regression: snooze id was hardcoded to offset 0, so two snoozed offsets
      // of one follow-up resolved to the same id and clobbered each other.
      final id5 = alarmIdFor('lead-1', followUp, 5, snooze: true);
      final id10 = alarmIdFor('lead-1', followUp, 10, snooze: true);
      expect(id5, isNot(id10));
    });

    test('tryDecode returns null on empty/garbage', () {
      expect(FollowUpAlarmPayload.tryDecode(null), isNull);
      expect(FollowUpAlarmPayload.tryDecode(''), isNull);
      expect(FollowUpAlarmPayload.tryDecode('not json'), isNull);
    });
  });

  group('humanOffsetLabel', () {
    test('formats minutes and hours', () {
      expect(humanOffsetLabel(1), '1 minute');
      expect(humanOffsetLabel(10), '10 minutes');
      expect(humanOffsetLabel(60), '1 hour');
      expect(humanOffsetLabel(90), '1 hour 30 minutes');
    });
  });
}
