// Story 7.1 — Personal performance stats for the Employee home card.
// Mirrors the get_my_motivation_stats() RPC return shape.

class MotivationStats {
  final int soldThisMonth;
  final int followupStreakDays;
  final double conversionRate; // percentage, one decimal (e.g. 12.5)
  final int totalAssigned;
  final DateTime fetchedAt;

  const MotivationStats({
    required this.soldThisMonth,
    required this.followupStreakDays,
    required this.conversionRate,
    required this.totalAssigned,
    required this.fetchedAt,
  });

  /// A zeroed snapshot for the no-cache fetch-failure path (AC-6).
  factory MotivationStats.zero() => MotivationStats(
        soldThisMonth: 0,
        followupStreakDays: 0,
        conversionRate: 0.0,
        totalAssigned: 0,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// From the RPC row. Postgres `numeric` arrives as either num or String —
  /// handle both. Ints arrive as int but guard defensively.
  factory MotivationStats.fromJson(Map<String, dynamic> j, {DateTime? fetchedAt}) {
    return MotivationStats(
      soldThisMonth: _asInt(j['sold_this_month']),
      followupStreakDays: _asInt(j['followup_streak_days']),
      conversionRate: _asDouble(j['conversion_rate']),
      totalAssigned: _asInt(j['total_assigned']),
      fetchedAt: fetchedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toCacheJson() => {
        'sold_this_month': soldThisMonth,
        'followup_streak_days': followupStreakDays,
        'conversion_rate': conversionRate,
        'total_assigned': totalAssigned,
        'fetched_at': fetchedAt.toIso8601String(),
      };

  factory MotivationStats.fromCacheJson(Map<String, dynamic> j) => MotivationStats(
        soldThisMonth: _asInt(j['sold_this_month']),
        followupStreakDays: _asInt(j['followup_streak_days']),
        conversionRate: _asDouble(j['conversion_rate']),
        totalAssigned: _asInt(j['total_assigned']),
        // Corrupt/missing fetched_at → epoch (not now()) so the UI can detect and hide
        // the "Updated …" subtitle rather than report a fresh fetch that never happened.
        fetchedAt: DateTime.tryParse(j['fetched_at'] as String? ?? '')
            ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
