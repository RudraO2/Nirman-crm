// Story 10.2 — Pure alarm-planning logic (no plugin imports, fully testable).
//
// Given a follow-up and the user's enabled offsets, produces the concrete set of
// alarms to schedule: one per offset, each firing `offset` minutes before the
// follow-up, skipping any whose fire time is already in the past (AC: no spurious
// immediate ring). Also owns the deterministic alarm-id derivation and the
// human-readable offset label shown on the ring screen.

import 'models/follow_up_alarm.dart';

/// Snooze re-ring interval (AC: "a short fixed interval, e.g. 5 min").
const Duration kAlarmSnoozeInterval = Duration(minutes: 5);

class PlannedAlarm {
  /// Stable platform alarm id (positive 31-bit int required by the plugin).
  final int id;

  /// When the alarm should ring (= followUpAt − offset).
  final DateTime fireTime;

  final FollowUpAlarmPayload payload;

  const PlannedAlarm({
    required this.id,
    required this.fireTime,
    required this.payload,
  });
}

/// Builds the alarms to schedule for one follow-up. Empty when alarms are off,
/// no offsets are chosen, or every computed fire time is already past.
List<PlannedAlarm> planFollowUpAlarms({
  required String leadId,
  required String leadName,
  required DateTime followUpAt,
  required List<int> offsetsMinutes,
  required DateTime now,
}) {
  final planned = <PlannedAlarm>[];
  for (final offset in offsetsMinutes) {
    final fireTime = followUpAt.subtract(Duration(minutes: offset));
    if (!fireTime.isAfter(now)) continue; // past → skip (AC)
    planned.add(
      PlannedAlarm(
        id: alarmIdFor(leadId, followUpAt, offset),
        fireTime: fireTime,
        payload: FollowUpAlarmPayload(
          leadId: leadId,
          leadName: leadName,
          followUpAt: followUpAt,
          offsetMinutes: offset,
        ),
      ),
    );
  }
  return planned;
}

/// Deterministic positive 31-bit id from (lead, follow-up time, offset). Stable
/// across runs (FNV-1a, not String.hashCode) so Story 10.3 can recompute the id
/// to cancel/reschedule a specific follow-up's alarms. [snooze] yields a
/// distinct id so a snooze re-ring never collides with an original offset alarm.
int alarmIdFor(
  String leadId,
  DateTime followUpAt,
  int offsetMinutes, {
  bool snooze = false,
}) {
  final key =
      '$leadId|${followUpAt.toIso8601String()}|$offsetMinutes|${snooze ? 's' : 'o'}';
  return _fnv1a(key) & 0x7fffffff;
}

int _fnv1a(String s) {
  const int prime = 0x01000193;
  int hash = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    hash = (hash ^ unit) * prime;
    hash &= 0xffffffff;
  }
  return hash;
}

/// "1 minute" / "10 minutes" / "1 hour" / "1 hour 30 minutes" — used in the ring
/// screen line "Rings <label> before your follow-up".
String humanOffsetLabel(int minutes) {
  if (minutes <= 0) return 'now';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final parts = <String>[];
  if (h > 0) parts.add('$h ${h == 1 ? 'hour' : 'hours'}');
  if (m > 0) parts.add('$m ${m == 1 ? 'minute' : 'minutes'}');
  return parts.join(' ');
}
