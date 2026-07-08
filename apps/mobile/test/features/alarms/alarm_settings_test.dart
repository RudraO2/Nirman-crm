// Story 10.1 — AlarmSettings model unit tests (normalize / offset toggle / encode).

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/alarms/data/models/alarm_settings.dart';

void main() {
  group('AlarmSettings', () {
    test('default is disabled with no offsets', () {
      const s = AlarmSettings.initial;
      expect(s.enabled, isFalse);
      expect(s.offsetsMinutes, isEmpty);
    });

    test('copyWith normalizes offsets: sorted, de-duped, clamped', () {
      final s = const AlarmSettings()
          .copyWith(offsetsMinutes: [30, 5, 5, 0, -3, 10, 99999]);
      // 0, -3 dropped (non-positive); 99999 dropped (> 24h); 5 de-duped.
      expect(s.offsetsMinutes, [5, 10, 30]);
    });

    test('withOffset adds and removes', () {
      var s = const AlarmSettings(enabled: true);
      s = s.withOffset(10, true);
      s = s.withOffset(1, true);
      expect(s.offsetsMinutes, [1, 10]);
      s = s.withOffset(10, false);
      expect(s.offsetsMinutes, [1]);
    });

    test('removing the master flag does not touch offsets', () {
      final s = const AlarmSettings(enabled: true, offsetsMinutes: [5])
          .copyWith(enabled: false);
      expect(s.enabled, isFalse);
      expect(s.offsetsMinutes, [5]);
    });

    test('string encode/decode round-trips', () {
      final s = const AlarmSettings().copyWith(offsetsMinutes: [30, 1, 10]);
      expect(s.offsetsAsStrings, ['1', '10', '30']);
      expect(AlarmSettings.offsetsFromStrings(['30', 'bad', '1']), [1, 30]);
      expect(AlarmSettings.offsetsFromStrings(null), isEmpty);
    });

    test('value equality ignores list identity', () {
      expect(
        const AlarmSettings(enabled: true, offsetsMinutes: [1, 5]),
        const AlarmSettings(enabled: true, offsetsMinutes: [1, 5]),
      );
    });
  });
}
