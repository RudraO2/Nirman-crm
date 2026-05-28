// Story 7.2 — SoldCelebration model + personal-record logic tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/motivation/data/models/sold_celebration.dart';

void main() {
  group('SoldCelebration.fromRpc — values', () {
    test('parses days and action count', () {
      final s = SoldCelebration.fromRpc({
        'days_to_close': 12,
        'action_count': 7,
        'sold_this_month': 1,
        'is_fastest_quarter': false,
      });
      expect(s.daysToClose, 12);
      expect(s.actionCount, 7);
    });

    test('tolerates numeric-as-num', () {
      final s = SoldCelebration.fromRpc({
        'days_to_close': 3.0,
        'action_count': 4.0,
        'sold_this_month': 0,
        'is_fastest_quarter': false,
      });
      expect(s.daysToClose, 3);
      expect(s.actionCount, 4);
    });
  });

  group('personal record line', () {
    test('fastest quarter wins over month count', () {
      final s = SoldCelebration.fromRpc({
        'days_to_close': 1,
        'action_count': 2,
        'sold_this_month': 5,
        'is_fastest_quarter': true,
      });
      expect(s.personalRecord, 'Your fastest close this quarter');
    });

    test('Nth close this month when not fastest and >=2', () {
      final s = SoldCelebration.fromRpc({
        'days_to_close': 9,
        'action_count': 3,
        'sold_this_month': 3,
        'is_fastest_quarter': false,
      });
      expect(s.personalRecord, 'Your 3rd close this month');
    });

    test('no record line for first close of the month, not fastest', () {
      final s = SoldCelebration.fromRpc({
        'days_to_close': 9,
        'action_count': 3,
        'sold_this_month': 1,
        'is_fastest_quarter': false,
      });
      expect(s.personalRecord, isNull);
    });

    test('ordinals: 1st 2nd 3rd 4th 11th 21st 22nd', () {
      String? recordFor(int n) => SoldCelebration.fromRpc({
            'days_to_close': 0,
            'action_count': 0,
            'sold_this_month': n,
            'is_fastest_quarter': false,
          }).personalRecord;
      expect(recordFor(2), 'Your 2nd close this month');
      expect(recordFor(3), 'Your 3rd close this month');
      expect(recordFor(4), 'Your 4th close this month');
      expect(recordFor(11), 'Your 11th close this month');
      expect(recordFor(21), 'Your 21st close this month');
      expect(recordFor(22), 'Your 22nd close this month');
    });
  });

  group('empty', () {
    test('empty is zeros with no record', () {
      expect(SoldCelebration.empty.daysToClose, 0);
      expect(SoldCelebration.empty.actionCount, 0);
      expect(SoldCelebration.empty.personalRecord, isNull);
    });
  });
}
