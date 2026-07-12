// Offline resilience (Phase 0 read cache + Phase 1 write queue) unit tests.
// path_provider is faked to a temp dir so the store's JSON files are real.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:nirman_crm/core/offline/offline_store.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('offline_store_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    OfflineStore.instance.banner.value = null;
    // isolate every test from files left by the previous one
    for (final f in tmp.listSync()) {
      f.deleteSync(recursive: true);
    }
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('isNetworkError', () {
    test('transport failures are network errors', () {
      expect(OfflineStore.isNetworkError(const SocketException('down')), isTrue);
      expect(OfflineStore.isNetworkError(TimeoutException('slow')), isTrue);
      expect(
        OfflineStore.isNetworkError(Exception('ClientException: Failed host lookup')),
        isTrue,
      );
    });

    test('server answers are NOT network errors', () {
      expect(OfflineStore.isNetworkError(Exception('permission_denied')), isFalse);
      expect(OfflineStore.isNetworkError(StateError('bad state')), isFalse);
    });
  });

  group('leads cache (Phase 0)', () {
    test('round-trips rows + patch + remove', () async {
      await OfflineStore.instance.cacheLeads([
        {'id': 'a', 'status': 'warm', 'name': 'Asha'},
        {'id': 'b', 'status': 'hot', 'name': 'Bina'},
      ]);
      var cached = await OfflineStore.instance.readCachedLeads();
      expect(cached, isNotNull);
      expect(cached!.rows.length, 2);

      await OfflineStore.instance
          .patchCachedLead('a', {'status': 'hot', 'pending_outcome_at': null});
      await OfflineStore.instance.removeCachedLead('b');
      cached = await OfflineStore.instance.readCachedLeads();
      expect(cached!.rows.length, 1);
      expect(cached.rows.single['id'], 'a');
      expect(cached.rows.single['status'], 'hot');
      expect(cached.rows.single['name'], 'Asha', reason: 'patch merges, not replaces');
    });

    test('no cache file reads as null', () async {
      expect(await OfflineStore.instance.readCachedLeads(), isNull);
    });
  });

  group('write queue (Phase 1)', () {
    test('flush replays in order and drains', () async {
      await OfflineStore.instance.enqueue('set_followup', {'p_lead_id': 'l1'});
      await OfflineStore.instance.enqueue('mark_lead_dead', {'p_lead_id': 'l2'});

      final calls = <String>[];
      final result = await OfflineStore.instance.flush(
        (fn, {params}) async => calls.add(fn),
      );

      expect(calls, ['set_followup', 'mark_lead_dead'], reason: 'strict FIFO');
      expect(result.replayed, 2);
      expect(result.dropped, 0);
      expect(await OfflineStore.instance.pendingCount(), 0);
    });

    test('network error stops the flush and keeps the remainder', () async {
      await OfflineStore.instance.enqueue('a', {});
      await OfflineStore.instance.enqueue('b', {});

      var first = true;
      final result = await OfflineStore.instance.flush((fn, {params}) async {
        if (first) {
          first = false;
          return;
        }
        throw const SocketException('still offline');
      });

      expect(result.replayed, 1);
      expect(await OfflineStore.instance.pendingCount(), 1,
          reason: 'b survives for the next flush');
    });

    test('server rejection drops the action (server is the arbiter)', () async {
      await OfflineStore.instance.enqueue('a', {});
      await OfflineStore.instance.enqueue('b', {});

      final calls = <String>[];
      final result = await OfflineStore.instance.flush((fn, {params}) async {
        calls.add(fn);
        if (fn == 'a') throw Exception('lead_reassigned');
      });

      expect(result.dropped, 1);
      expect(result.replayed, 1);
      expect(calls, ['a', 'b'], reason: 'rejection must not block the queue');
      expect(await OfflineStore.instance.pendingCount(), 0);
    });
  });
}
