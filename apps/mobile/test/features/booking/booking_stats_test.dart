// Story 15.5-mobile — BookingStats parsing + conversion label.

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/booking/data/models/booking_stats.dart';

void main() {
  test('fromJson maps counts + numeric conversion_pct', () {
    final s = BookingStats.fromJson({
      'confirmed_bookings': 1,
      'active_holds': 1,
      'total_holds': 2,
      'conversion_pct': 50.0,
    });
    expect(s.confirmedBookings, 1);
    expect(s.activeHolds, 1);
    expect(s.totalHolds, 2);
    expect(s.conversionPct, 50.0);
  });

  test('conversion_pct as string (PostgREST numeric) parses to double', () {
    final s = BookingStats.fromJson({
      'confirmed_bookings': 1,
      'active_holds': 0,
      'total_holds': 3,
      'conversion_pct': '33.3',
    });
    expect(s.conversionPct, closeTo(33.3, 0.001));
  });

  test('null conversion_pct (no holds in period) → 0', () {
    final s = BookingStats.fromJson({
      'confirmed_bookings': 0,
      'active_holds': 0,
      'total_holds': 0,
      'conversion_pct': null,
    });
    expect(s.conversionPct, 0);
  });

  test('conversionLabel trims a whole number, keeps a fraction', () {
    expect(const BookingStats(
            confirmedBookings: 1, activeHolds: 1, totalHolds: 2, conversionPct: 50)
        .conversionLabel, '50%');
    expect(const BookingStats(
            confirmedBookings: 1, activeHolds: 0, totalHolds: 3, conversionPct: 33.3)
        .conversionLabel, '33.3%');
  });
}
