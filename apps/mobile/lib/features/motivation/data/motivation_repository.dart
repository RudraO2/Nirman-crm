// Story 7.1 — Motivation stats repository.
// Fetches get_my_motivation_stats() RPC; caches the last good snapshot in
// secure storage so the home card can show last-known values when offline (AC-6).

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/motivation_stats.dart';

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
}

@riverpod
MotivationRepository motivationRepository(MotivationRepositoryRef ref) {
  return MotivationRepository(Supabase.instance.client);
}
