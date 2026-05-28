// Story 7.4 — MonthlyBest model + derived-flag tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/motivation/data/models/monthly_best.dart';

void main() {
  MonthlyBest mb({int thisM = 0, int lastM = 0, int best = 0, int day = 15}) =>
      MonthlyBest.fromRpc({
        'this_month_sold': thisM,
        'last_month_sold': lastM,
        'all_time_best': best,
        'day_of_month': day,
      });

  group('fromRpc', () {
    test('parses all fields', () {
      final m = mb(thisM: 4, lastM: 6, best: 9, day: 3);
      expect(m.thisMonthSold, 4);
      expect(m.lastMonthSold, 6);
      expect(m.allTimeBest, 9);
      expect(m.dayOfMonth, 3);
    });
  });

  group('showPreviousMonthCard (first 7 days)', () {
    test('day 1 and day 7 show', () {
      expect(mb(day: 1).showPreviousMonthCard, isTrue);
      expect(mb(day: 7).showPreviousMonthCard, isTrue);
    });
    test('day 8 and later hide', () {
      expect(mb(day: 8).showPreviousMonthCard, isFalse);
      expect(mb(day: 28).showPreviousMonthCard, isFalse);
    });
  });

  group('isNewBest', () {
    test('this month beats prior best', () {
      expect(mb(thisM: 5, best: 4).isNewBest, isTrue);
    });
    test('equal to best is not a new best', () {
      expect(mb(thisM: 4, best: 4).isNewBest, isFalse);
    });
    test('zero closes is never a new best', () {
      expect(mb(thisM: 0, best: 0).isNewBest, isFalse);
    });
    test('first ever close (best 0) is a new best', () {
      expect(mb(thisM: 1, best: 0).isNewBest, isTrue);
    });
  });

  test('empty is all zeros, no card, no banner', () {
    expect(MonthlyBest.empty.showPreviousMonthCard, isFalse);
    expect(MonthlyBest.empty.isNewBest, isFalse);
  });
}
