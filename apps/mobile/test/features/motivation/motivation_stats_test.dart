// Story 7.1 — MotivationStats parsing tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/motivation/data/models/motivation_stats.dart';

void main() {
  group('MotivationStats.fromJson', () {
    test('parses conversion_rate when it arrives as a num', () {
      final s = MotivationStats.fromJson({
        'sold_this_month': 3,
        'followup_streak_days': 5,
        'conversion_rate': 12.5,
        'total_assigned': 24,
      });
      expect(s.soldThisMonth, 3);
      expect(s.followupStreakDays, 5);
      expect(s.conversionRate, 12.5);
      expect(s.totalAssigned, 24);
    });

    test('parses conversion_rate when Postgres numeric arrives as a String', () {
      final s = MotivationStats.fromJson({
        'sold_this_month': 0,
        'followup_streak_days': 0,
        'conversion_rate': '0.0',
        'total_assigned': 0,
      });
      expect(s.conversionRate, 0.0);
    });

    test('null / missing conversion_rate yields 0.0 (no NaN)', () {
      final s = MotivationStats.fromJson({
        'sold_this_month': 1,
        'followup_streak_days': 2,
        'conversion_rate': null,
        'total_assigned': 10,
      });
      expect(s.conversionRate, 0.0);
      expect(s.conversionRate.isNaN, isFalse);
    });

    test('int fields tolerate num input', () {
      final s = MotivationStats.fromJson({
        'sold_this_month': 2.0,
        'followup_streak_days': 7.0,
        'conversion_rate': 8.3,
        'total_assigned': 30.0,
      });
      expect(s.soldThisMonth, 2);
      expect(s.followupStreakDays, 7);
      expect(s.totalAssigned, 30);
    });
  });

  group('cache round-trip', () {
    test('toCacheJson → fromCacheJson preserves values and fetchedAt', () {
      final t = DateTime(2026, 5, 28, 10, 30);
      final original = MotivationStats(
        soldThisMonth: 4,
        followupStreakDays: 9,
        conversionRate: 15.4,
        totalAssigned: 26,
        fetchedAt: t,
      );
      final restored = MotivationStats.fromCacheJson(original.toCacheJson());
      expect(restored.soldThisMonth, 4);
      expect(restored.followupStreakDays, 9);
      expect(restored.conversionRate, 15.4);
      expect(restored.totalAssigned, 26);
      expect(restored.fetchedAt, t);
    });
  });

  group('zero', () {
    test('zero() is all zeros with epoch timestamp', () {
      final z = MotivationStats.zero();
      expect(z.soldThisMonth, 0);
      expect(z.followupStreakDays, 0);
      expect(z.conversionRate, 0.0);
      expect(z.totalAssigned, 0);
      expect(z.fetchedAt.millisecondsSinceEpoch, 0);
    });
  });
}
