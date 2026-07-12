// Offline resilience (practicality backlog P0/P1, 2026-07-12).
//
// Phase 0 — read cache: the last successful get_my_leads result is persisted as
// raw JSON rows (app-private support dir — same trust boundary as the alarm
// payloads) and served when the network is down, with a banner state the home
// screen renders ("offline — synced X ago").
//
// Phase 1 — write queue: the three high-frequency field actions (mark dead,
// set follow-up, call outcome) enqueue their EXACT rpc call when the failure is
// a network error (never on a server rejection — those are real answers) and
// replay IN ORDER next time the app can reach the server. Server guards
// (status rules, reassignment) stay the arbiter on replay; a rejected replay is
// dropped and counted, never retried forever.
//
// No new dependencies: JSON files via path_provider, ValueNotifier for UI state.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Thrown by repository writes when the action could not reach the server and
/// was queued for replay. UIs treat this as "saved offline", not an error.
class OfflineQueued implements Exception {
  const OfflineQueued();
}

/// What the home banner renders. null = live data, no banner.
class OfflineBannerState {
  final DateTime syncedAt;
  final int pendingActions;
  const OfflineBannerState({required this.syncedAt, required this.pendingActions});
}

class CachedLeads {
  final List<Map<String, dynamic>> rows;
  final DateTime syncedAt;
  const CachedLeads({required this.rows, required this.syncedAt});
}

class PendingAction {
  final String rpc;
  final Map<String, dynamic> params;
  final DateTime queuedAt;
  const PendingAction({required this.rpc, required this.params, required this.queuedAt});

  Map<String, dynamic> toJson() => {
        'rpc': rpc,
        'params': params,
        'queued_at': queuedAt.toIso8601String(),
      };

  static PendingAction fromJson(Map<String, dynamic> m) => PendingAction(
        rpc: m['rpc'] as String,
        params: Map<String, dynamic>.from(m['params'] as Map),
        queuedAt: DateTime.tryParse(m['queued_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class OfflineStore {
  OfflineStore._();
  static final OfflineStore instance = OfflineStore._();

  /// Home-screen banner state. Non-null while the list on screen came from the
  /// cache and/or writes are waiting to sync.
  final ValueNotifier<OfflineBannerState?> banner = ValueNotifier(null);

  static const _cacheFile = 'offline_leads_cache.json';
  static const _queueFile = 'offline_action_queue.json';

  bool _flushing = false;

  /// True for transport-level failures (no network / DNS / timeout). Server
  /// responses of any status are NOT network errors — they are real answers.
  static bool isNetworkError(Object e) {
    if (e is SocketException || e is TimeoutException || e is HandshakeException) {
      return true;
    }
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection closed') ||
        s.contains('Connection reset') ||
        s.contains('Network is unreachable');
  }

  Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$name');
  }

  // ── Phase 0: leads read cache ──────────────────────────────────────────────

  Future<void> cacheLeads(List<Map<String, dynamic>> rawRows) async {
    try {
      final f = await _file(_cacheFile);
      await f.writeAsString(jsonEncode({
        'synced_at': DateTime.now().toIso8601String(),
        'rows': rawRows,
      }));
    } catch (_) {
      // Cache write failure must never break a successful fetch.
    }
  }

  Future<CachedLeads?> readCachedLeads() async {
    try {
      final f = await _file(_cacheFile);
      if (!await f.exists()) return null;
      final decoded = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final syncedAt = DateTime.tryParse(decoded['synced_at'] as String? ?? '');
      final rows = (decoded['rows'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      if (syncedAt == null) return null;
      return CachedLeads(rows: rows, syncedAt: syncedAt);
    } catch (_) {
      return null; // corrupt cache reads as "no cache"
    }
  }

  /// Optimistically patch one cached lead row so a queued write is reflected
  /// in the offline list (e.g. dead lead disappears, follow-up date updates)
  /// instead of resurrecting on the next cache-served refresh.
  Future<void> patchCachedLead(String leadId, Map<String, dynamic> patch) async {
    final cached = await readCachedLeads();
    if (cached == null) return;
    final rows = cached.rows.map((r) {
      if (r['id'] == leadId) return {...r, ...patch};
      return r;
    }).toList();
    await _writeCache(rows, cached.syncedAt);
  }

  Future<void> removeCachedLead(String leadId) async {
    final cached = await readCachedLeads();
    if (cached == null) return;
    final rows = cached.rows.where((r) => r['id'] != leadId).toList();
    await _writeCache(rows, cached.syncedAt);
  }

  Future<void> _writeCache(List<Map<String, dynamic>> rows, DateTime syncedAt) async {
    try {
      final f = await _file(_cacheFile);
      await f.writeAsString(jsonEncode({
        'synced_at': syncedAt.toIso8601String(),
        'rows': rows,
      }));
    } catch (_) {}
  }

  /// Fetch succeeded — clear the banner (keep it if writes are still pending).
  Future<void> markLive() async {
    final pending = (await _readQueue()).length;
    banner.value = pending == 0
        ? null
        : OfflineBannerState(syncedAt: DateTime.now(), pendingActions: pending);
  }

  Future<void> markServingCache(DateTime syncedAt) async {
    final pending = (await _readQueue()).length;
    banner.value = OfflineBannerState(syncedAt: syncedAt, pendingActions: pending);
  }

  // ── Phase 1: write queue ───────────────────────────────────────────────────

  Future<List<PendingAction>> _readQueue() async {
    try {
      final f = await _file(_queueFile);
      if (!await f.exists()) return [];
      final decoded = jsonDecode(await f.readAsString()) as List;
      return decoded
          .map((e) => PendingAction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeQueue(List<PendingAction> q) async {
    final f = await _file(_queueFile);
    await f.writeAsString(jsonEncode(q.map((a) => a.toJson()).toList()));
  }

  Future<int> pendingCount() async => (await _readQueue()).length;

  Future<void> enqueue(String rpc, Map<String, dynamic> params) async {
    final q = await _readQueue();
    q.add(PendingAction(rpc: rpc, params: params, queuedAt: DateTime.now()));
    await _writeQueue(q);
    final current = banner.value;
    banner.value = OfflineBannerState(
      syncedAt: current?.syncedAt ?? DateTime.now(),
      pendingActions: q.length,
    );
  }

  /// Replays the queue in order through [rpc] (injected for testability;
  /// production passes `supabase.rpc`). Stops at the first NETWORK error
  /// (still offline — keep the rest). A server rejection drops the action
  /// (the server is the arbiter; e.g. the lead was reassigned meanwhile).
  /// Returns (replayed, dropped).
  Future<({int replayed, int dropped})> flush(
    Future<dynamic> Function(String fn, {Map<String, dynamic>? params}) rpc,
  ) async {
    if (_flushing) return (replayed: 0, dropped: 0);
    _flushing = true;
    try {
      var q = await _readQueue();
      var replayed = 0;
      var dropped = 0;
      while (q.isNotEmpty) {
        final action = q.first;
        try {
          await rpc(action.rpc, params: action.params);
          replayed++;
        } catch (e) {
          if (isNetworkError(e)) {
            break; // still offline — try again later, keep order
          }
          dropped++; // server said no — do not retry forever
          debugPrint('offline_queue: dropped ${action.rpc} (${e.runtimeType})');
        }
        q = q.sublist(1);
        await _writeQueue(q);
      }
      // Only update the banner when this flush actually did something — an
      // empty-queue flush proves nothing about connectivity, and the banner's
      // offline/synced-at state belongs to markLive()/markServingCache().
      final current = banner.value;
      if ((replayed > 0 || dropped > 0) && current != null) {
        banner.value = OfflineBannerState(
          syncedAt: current.syncedAt,
          pendingActions: q.length,
        );
      }
      return (replayed: replayed, dropped: dropped);
    } finally {
      _flushing = false;
    }
  }
}
