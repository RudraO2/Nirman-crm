// Story 16.2-mobile — ExecutionAmendment parsing + AmendmentStatus lifecycle.

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/amendments/data/models/execution_amendment.dart';

void main() {
  group('ExecutionAmendment.fromJson', () {
    test('maps PII-free columns + parses status', () {
      final a = ExecutionAmendment.fromJson({
        'amendment_id': 'am1',
        'unit_id': 'u1',
        'unit_no': '102',
        'configuration': '3BHK',
        'lead_id': 'l1',
        'description': 'East-facing balcony',
        'status': 'in_progress',
        'created_at': '2026-07-11T09:00:00Z',
        'updated_at': '2026-07-11T10:00:00Z',
      });
      expect(a.unitNo, '102');
      expect(a.configuration, '3BHK');
      expect(a.status, AmendmentStatus.inProgress);
      // No name/phone fields exist on the model (PII minimization).
    });

    test('null configuration tolerated', () {
      final a = ExecutionAmendment.fromJson({
        'amendment_id': 'am1',
        'unit_id': 'u1',
        'unit_no': '102',
        'configuration': null,
        'lead_id': 'l1',
        'description': 'x',
        'status': 'requested',
        'created_at': '2026-07-11T09:00:00Z',
        'updated_at': '2026-07-11T09:00:00Z',
      });
      expect(a.configuration, isNull);
      expect(a.status, AmendmentStatus.requested);
    });
  });

  group('AmendmentStatus lifecycle', () {
    test('dbValue round-trips via fromDb', () {
      for (final s in AmendmentStatus.values) {
        expect(AmendmentStatus.fromDb(s.dbValue), s);
      }
    });

    test('nextStatuses match the RPC transitions', () {
      expect(AmendmentStatus.requested.nextStatuses,
          [AmendmentStatus.acknowledged, AmendmentStatus.rejected]);
      expect(AmendmentStatus.acknowledged.nextStatuses,
          [AmendmentStatus.inProgress, AmendmentStatus.rejected]);
      expect(AmendmentStatus.inProgress.nextStatuses,
          [AmendmentStatus.done, AmendmentStatus.rejected]);
      expect(AmendmentStatus.done.nextStatuses, isEmpty);
      expect(AmendmentStatus.rejected.nextStatuses, isEmpty);
    });

    test('terminal states', () {
      expect(AmendmentStatus.done.isTerminal, isTrue);
      expect(AmendmentStatus.rejected.isTerminal, isTrue);
      expect(AmendmentStatus.requested.isTerminal, isFalse);
    });

    test('unknown db value → requested fallback', () {
      expect(AmendmentStatus.fromDb('gibberish'), AmendmentStatus.requested);
      expect(AmendmentStatus.fromDb(null), AmendmentStatus.requested);
    });
  });
}
