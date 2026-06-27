// Bug fix — 100-lead cap. getAllMyLeads pages get_my_leads until exhausted so the
// home screen loads the COMPLETE active set (Today counts + alarm reconcile fold
// over the whole list). Tests the pure paging loop LeadRepository.collectPages.
// Run with: flutter test test/features/leads/lead_repository_paging_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/leads/data/lead_repository.dart';

void main() {
  // Builds a fetcher over an in-memory list, recording each (limit, offset) call.
  ({Future<List<int>> Function(int, int) fetch, List<List<int>> calls})
      fakeSource(int total) {
    final data = List<int>.generate(total, (i) => i);
    final calls = <List<int>>[];
    Future<List<int>> fetch(int limit, int offset) async {
      calls.add([limit, offset]);
      return data.skip(offset).take(limit).toList();
    }
    return (fetch: fetch, calls: calls);
  }

  group('LeadRepository.collectPages', () {
    test('returns all rows across multiple pages', () async {
      final src = fakeSource(450);
      final all = await LeadRepository.collectPages(src.fetch, pageSize: 200);
      expect(all.length, 450);
      expect(all, List<int>.generate(450, (i) => i));
      // 200, 200, 50 → 3 fetches at offsets 0/200/400.
      expect(src.calls, [[200, 0], [200, 200], [200, 400]]);
    });

    test('single short page stops after one fetch', () async {
      final src = fakeSource(30);
      final all = await LeadRepository.collectPages(src.fetch, pageSize: 200);
      expect(all.length, 30);
      expect(src.calls, [[200, 0]]);
    });

    test('empty source returns empty after one fetch', () async {
      final src = fakeSource(0);
      final all = await LeadRepository.collectPages(src.fetch, pageSize: 200);
      expect(all, isEmpty);
      expect(src.calls, [[200, 0]]);
    });

    test('exact multiple of pageSize does an extra empty fetch then stops', () async {
      final src = fakeSource(400);
      final all = await LeadRepository.collectPages(src.fetch, pageSize: 200);
      expect(all.length, 400);
      // Full page at 0 and 200, then empty page at 400 signals end.
      expect(src.calls, [[200, 0], [200, 200], [200, 400]]);
    });

    test('no rows are dropped or duplicated past the old 100 cap', () async {
      final src = fakeSource(237);
      final all = await LeadRepository.collectPages(src.fetch, pageSize: 100);
      expect(all.toSet().length, 237); // unique
      expect(all.length, 237);
    });
  });
}
