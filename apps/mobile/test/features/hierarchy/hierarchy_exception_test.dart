// Story 12.4-mobile — HierarchyException.friendly maps each RPC guard token.

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/hierarchy/data/hierarchy_repository.dart';

void main() {
  test('permission denied → builder-head message', () {
    const e = HierarchyException('permission_denied', permissionDenied: true);
    expect(e.friendly, contains('builder-head'));
  });

  test('maps each known guard token to a calm sentence', () {
    expect(const HierarchyException('reporting_cycle_detected').friendly,
        contains('loop'));
    expect(const HierarchyException('reports_to_must_be_higher_tier').friendly,
        contains('higher tier'));
    expect(
        const HierarchyException('off_ladder_tier_has_no_reports_to').friendly,
        contains("don't report"));
    expect(const HierarchyException('cannot_report_to_self').friendly,
        contains('themselves'));
    expect(const HierarchyException('agency_required_for_partner').friendly,
        contains('agency'));
    expect(const HierarchyException('agency_not_found').friendly,
        contains('no longer exists'));
    expect(const HierarchyException('user_not_found').friendly,
        contains('no longer in your organisation'));
  });

  test('unknown token → generic fallback (never a raw dump)', () {
    final f = const HierarchyException('some_pg_internal_42P01').friendly;
    expect(f, "Couldn't save the change. Please try again.");
  });
}
