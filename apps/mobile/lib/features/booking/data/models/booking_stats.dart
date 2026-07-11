// Story 15.5-mobile — booking stats from get_booking_stats.
//
// Mirrors the RPC's RETURNS TABLE (confirmed_bookings, active_holds, total_holds,
// conversion_pct). conversion_pct is a numeric that PostgREST returns as num/String;
// null (no holds in the period) → 0. Flutter-free.

class BookingStats {
  final int confirmedBookings;
  final int activeHolds;
  final int totalHolds;
  final double conversionPct;

  const BookingStats({
    required this.confirmedBookings,
    required this.activeHolds,
    required this.totalHolds,
    required this.conversionPct,
  });

  static const empty = BookingStats(
    confirmedBookings: 0,
    activeHolds: 0,
    totalHolds: 0,
    conversionPct: 0,
  );

  factory BookingStats.fromJson(Map<String, dynamic> j) => BookingStats(
        confirmedBookings: (j['confirmed_bookings'] as num?)?.toInt() ?? 0,
        activeHolds: (j['active_holds'] as num?)?.toInt() ?? 0,
        totalHolds: (j['total_holds'] as num?)?.toInt() ?? 0,
        conversionPct: _toDouble(j['conversion_pct']),
      );

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  /// "50%" / "33.3%" — trims a trailing ".0".
  String get conversionLabel {
    final s = conversionPct == conversionPct.roundToDouble()
        ? conversionPct.toStringAsFixed(0)
        : conversionPct.toStringAsFixed(1);
    return '$s%';
  }
}
