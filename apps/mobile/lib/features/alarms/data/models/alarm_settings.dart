// Story 10.1 — Global follow-up alarm settings (device-local).
// Plain immutable value: master enable flag + the set of lead-time offsets
// (minutes before a follow-up) at which an alarm should ring. Persisted via
// AlarmSettingsRepository; read by the 10.2/10.3 scheduler (incl. bg isolate).

import 'package:flutter/foundation.dart';

/// Canonical preset offsets (minutes before follow-up) shown as chips.
const List<int> kAlarmPresetOffsets = [1, 5, 10, 30];

/// Upper sanity bound for a custom offset (24h).
const int kMaxAlarmOffsetMinutes = 1440;

@immutable
class AlarmSettings {
  /// Master toggle. Default OFF (AC1).
  final bool enabled;

  /// Sorted, de-duplicated lead-time offsets in minutes. Each enabled offset
  /// produces one alarm per follow-up (Story 10.2).
  final List<int> offsetsMinutes;

  const AlarmSettings({
    this.enabled = false,
    this.offsetsMinutes = const [],
  });

  /// Default: alarms off, no offsets.
  static const AlarmSettings initial = AlarmSettings();

  AlarmSettings copyWith({bool? enabled, List<int>? offsetsMinutes}) {
    return AlarmSettings(
      enabled: enabled ?? this.enabled,
      offsetsMinutes:
          offsetsMinutes == null ? this.offsetsMinutes : _normalize(offsetsMinutes),
    );
  }

  /// Returns a copy with [minutes] added or removed from the offset set.
  AlarmSettings withOffset(int minutes, bool on) {
    final next = {...offsetsMinutes};
    if (on) {
      next.add(minutes);
    } else {
      next.remove(minutes);
    }
    return copyWith(offsetsMinutes: next.toList());
  }

  /// Sort + de-dupe + clamp to (0, kMaxAlarmOffsetMinutes].
  static List<int> _normalize(Iterable<int> raw) {
    final set = raw
        .where((m) => m > 0 && m <= kMaxAlarmOffsetMinutes)
        .toSet()
        .toList()
      ..sort();
    return List.unmodifiable(set);
  }

  // --- primitive encode for shared_preferences (no JSON lib needed) ---
  List<String> get offsetsAsStrings =>
      offsetsMinutes.map((m) => m.toString()).toList();

  static List<int> offsetsFromStrings(List<String>? raw) =>
      _normalize((raw ?? const []).map((s) => int.tryParse(s) ?? -1));

  @override
  bool operator ==(Object other) =>
      other is AlarmSettings &&
      other.enabled == enabled &&
      listEquals(other.offsetsMinutes, offsetsMinutes);

  @override
  int get hashCode => Object.hash(enabled, Object.hashAll(offsetsMinutes));

  @override
  String toString() =>
      'AlarmSettings(enabled: $enabled, offsets: $offsetsMinutes)';
}
