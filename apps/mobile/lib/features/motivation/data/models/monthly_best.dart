// Story 7.4 — monthly personal-best figures for the home card + banner.

class MonthlyBest {
  final int thisMonthSold;
  final int lastMonthSold;
  final int allTimeBest;
  final int dayOfMonth;

  const MonthlyBest({
    required this.thisMonthSold,
    required this.lastMonthSold,
    required this.allTimeBest,
    required this.dayOfMonth,
  });

  static const empty = MonthlyBest(
    thisMonthSold: 0,
    lastMonthSold: 0,
    allTimeBest: 0,
    dayOfMonth: 0,
  );

  /// "Previous month" card shows only in the first 7 days of the month (AC-1/2).
  bool get showPreviousMonthCard => dayOfMonth >= 1 && dayOfMonth <= 7;

  /// New-best banner when this month's closes beat the prior all-time best (AC-3).
  bool get isNewBest => thisMonthSold > allTimeBest && thisMonthSold > 0;

  factory MonthlyBest.fromRpc(Map<String, dynamic> j) => MonthlyBest(
        thisMonthSold: _asInt(j['this_month_sold']),
        lastMonthSold: _asInt(j['last_month_sold']),
        allTimeBest: _asInt(j['all_time_best']),
        dayOfMonth: _asInt(j['day_of_month']),
      );

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
