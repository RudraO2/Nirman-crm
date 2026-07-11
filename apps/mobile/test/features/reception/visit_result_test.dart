// Story 13.4-mobile — VisitResult parsing + ordinal labelling.

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/reception/data/models/visit_result.dart';

void main() {
  test('fromJson maps lead_id + visit_count', () {
    final r = VisitResult.fromJson({'lead_id': 'abc', 'visit_count': 3});
    expect(r.leadId, 'abc');
    expect(r.visitCount, 3);
  });

  test('ordinal follows English rules incl. 11/12/13 exceptions', () {
    expect(VisitResult.ordinal(1), '1st');
    expect(VisitResult.ordinal(2), '2nd');
    expect(VisitResult.ordinal(3), '3rd');
    expect(VisitResult.ordinal(4), '4th');
    expect(VisitResult.ordinal(11), '11th');
    expect(VisitResult.ordinal(12), '12th');
    expect(VisitResult.ordinal(13), '13th');
    expect(VisitResult.ordinal(21), '21st');
    expect(VisitResult.ordinal(22), '22nd');
    expect(VisitResult.ordinal(113), '113th');
  });

  test('ordinalLabel composes "Nth visit"', () {
    expect(const VisitResult(leadId: 'x', visitCount: 2).ordinalLabel,
        '2nd visit');
    expect(const VisitResult(leadId: 'x', visitCount: 1).ordinalLabel,
        '1st visit');
  });
}
