// Story 10.2 — Payload carried by each scheduled follow-up alarm.
//
// Encoded into the `alarm` package's AlarmSettings.payload (a String) so that
// when an alarm rings — even after the app was killed — we can rebuild the ring
// screen (lead name, follow-up time, offset) and deep-link to the lead. Kept
// pure (no plugin imports) so it is unit-testable.

import 'dart:convert';

class FollowUpAlarmPayload {
  final String leadId;
  final String leadName;

  /// The follow-up's due time (NOT the alarm fire time — the alarm fires
  /// [offsetMinutes] before this).
  final DateTime followUpAt;

  /// Lead-time offset in minutes. 0 for a snooze re-ring.
  final int offsetMinutes;

  /// True when this is a snooze re-ring rather than an original offset alarm.
  final bool isSnooze;

  const FollowUpAlarmPayload({
    required this.leadId,
    required this.leadName,
    required this.followUpAt,
    required this.offsetMinutes,
    this.isSnooze = false,
  });

  /// Re-ring payload. Keeps [offsetMinutes] so the snooze alarm id stays
  /// distinct per original offset — zeroing it made two snoozed offsets of the
  /// same follow-up collide on one id. The ring screen keys its label off
  /// [isSnooze], so the retained offset is not shown to the user.
  FollowUpAlarmPayload asSnooze() => FollowUpAlarmPayload(
        leadId: leadId,
        leadName: leadName,
        followUpAt: followUpAt,
        offsetMinutes: offsetMinutes,
        isSnooze: true,
      );

  String encode() => jsonEncode({
        'leadId': leadId,
        'leadName': leadName,
        'followUpAt': followUpAt.toIso8601String(),
        'offsetMinutes': offsetMinutes,
        'isSnooze': isSnooze,
      });

  /// Returns null when [raw] is empty or not a valid payload (e.g. an alarm
  /// scheduled by some other path) so the caller can ring without a ring screen.
  static FollowUpAlarmPayload? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return FollowUpAlarmPayload(
        leadId: m['leadId'] as String,
        leadName: m['leadName'] as String,
        followUpAt: DateTime.parse(m['followUpAt'] as String),
        offsetMinutes: m['offsetMinutes'] as int,
        isSnooze: m['isSnooze'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FollowUpAlarmPayload &&
      other.leadId == leadId &&
      other.leadName == leadName &&
      other.followUpAt == followUpAt &&
      other.offsetMinutes == offsetMinutes &&
      other.isSnooze == isSnooze;

  @override
  int get hashCode =>
      Object.hash(leadId, leadName, followUpAt, offsetMinutes, isSnooze);
}
