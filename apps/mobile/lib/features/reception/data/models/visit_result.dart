// Story 13.4-mobile — result of a verify_visit RPC call.
//
// Mirrors the RPC's jsonb return `{lead_id, visit_count}`. Flutter-free so it stays
// unit-testable. PII-minimized by design: the receptionist gets only the lead id +
// the new visit count, never the name/phone (gate-not-own, 12.6).

class VisitResult {
  final String leadId;
  final int visitCount;

  const VisitResult({required this.leadId, required this.visitCount});

  factory VisitResult.fromJson(Map<String, dynamic> j) => VisitResult(
        leadId: j['lead_id'] as String,
        visitCount: j['visit_count'] as int,
      );

  /// Ordinal label for the current visit: 1 → "1st visit", 2 → "2nd visit", …
  /// English ordinal rules (11th/12th/13th are the -th exceptions).
  String get ordinalLabel => '${ordinal(visitCount)} visit';

  static String ordinal(int n) {
    if (n <= 0) return '$n';
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${n}th';
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
}
