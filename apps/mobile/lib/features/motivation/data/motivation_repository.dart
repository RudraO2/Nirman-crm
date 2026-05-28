// Story 7.1 — Motivation stats repository.
// Fetches get_my_motivation_stats() RPC; caches the last good snapshot in
// secure storage so the home card can show last-known values when offline (AC-6).

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/motivation_stats.dart';
import 'models/sold_celebration.dart';
import 'models/monthly_best.dart';

part 'motivation_repository.g.dart';

class MotivationRepository {
  final SupabaseClient _supabase;
  const MotivationRepository(this._supabase);

  static const _cacheKey = 'motivation_stats_v1';
  static const _storage = FlutterSecureStorage();

  /// Returns the caller's stats. On RPC failure, falls back to the last
  /// cached snapshot; if there is no cache, rethrows so the UI can show zeros.
  Future<MotivationStats> getMyStats() async {
    try {
      final result = await _supabase.rpc('get_my_motivation_stats');
      final rows = result as List;
      if (rows.isEmpty) {
        return MotivationStats.zero();
      }
      final stats = MotivationStats.fromJson(
        Map<String, dynamic>.from(rows.first as Map),
        fetchedAt: DateTime.now(),
      );
      await _storage.write(key: _cacheKey, value: jsonEncode(stats.toCacheJson()));
      return stats;
    } catch (_) {
      final cached = await _storage.read(key: _cacheKey);
      if (cached != null) {
        return MotivationStats.fromCacheJson(
          Map<String, dynamic>.from(jsonDecode(cached) as Map),
        );
      }
      rethrow;
    }
  }

  /// Earned-moment numbers for a just-sold lead (Story 7.2).
  /// Never throws — returns [SoldCelebration.empty] on any failure so the
  /// celebration moment is never blocked by a network hiccup.
  Future<SoldCelebration> fetchSoldCelebration(String leadId) async {
    try {
      final result = await _supabase.rpc(
        'get_sold_celebration',
        params: {'p_lead_id': leadId},
      );
      final rows = result as List;
      if (rows.isEmpty) return SoldCelebration.empty;
      return SoldCelebration.fromRpc(Map<String, dynamic>.from(rows.first as Map));
    } catch (_) {
      return SoldCelebration.empty;
    }
  }

  /// Monthly personal-best figures (Story 7.4). Returns [MonthlyBest.empty] on failure.
  Future<MonthlyBest> getMonthlyBest() async {
    try {
      final result = await _supabase.rpc('get_monthly_best');
      final rows = result as List;
      if (rows.isEmpty) return MonthlyBest.empty;
      return MonthlyBest.fromRpc(Map<String, dynamic>.from(rows.first as Map));
    } catch (_) {
      return MonthlyBest.empty;
    }
  }

  /// Fires the admin "[employee] just closed [lead]" push (Story 7.2).
  /// Best-effort — swallows errors so it never blocks the employee's flow.
  Future<void> notifyAdminSold(String leadId, String? leadName) async {
    try {
      await _supabase.functions.invoke('sold-celebrate-calc', body: {
        'lead_id': leadId,
        if (leadName != null && leadName.isNotEmpty) 'lead_name': leadName,
      });
    } catch (_) {
      // ignored — admin push is non-critical
    }
  }
}

@riverpod
MotivationRepository motivationRepository(MotivationRepositoryRef ref) {
  return MotivationRepository(Supabase.instance.client);
}
