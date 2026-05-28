// Story 7.2 — earned-moment payload for the Sold celebration card.
// Built from get_sold_celebration() RPC; the personal-record LINE is composed here.

class SoldCelebration {
  final int daysToClose;
  final int actionCount;
  final String? personalRecord;

  const SoldCelebration({
    required this.daysToClose,
    required this.actionCount,
    this.personalRecord,
  });

  static const empty = SoldCelebration(daysToClose: 0, actionCount: 0, personalRecord: null);

  factory SoldCelebration.fromRpc(Map<String, dynamic> j) {
    final days = _asInt(j['days_to_close']);
    final actions = _asInt(j['action_count']);
    final soldThisMonth = _asInt(j['sold_this_month']);
    final isFastest = j['is_fastest_quarter'] == true;
    return SoldCelebration(
      daysToClose: days,
      actionCount: actions,
      personalRecord: _record(isFastest: isFastest, soldThisMonth: soldThisMonth),
    );
  }

  // One line, priority: fastest-quarter → Nth-this-month → none.
  static String? _record({required bool isFastest, required int soldThisMonth}) {
    if (isFastest) return 'Your fastest close this quarter';
    if (soldThisMonth >= 2) return 'Your ${_ordinal(soldThisMonth)} close this month';
    return null;
  }

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
