// Story 7.1 — Motivation stats provider.
// Invalidate after any qualifying action (status change, follow-up, etc.) so the
// home stats card stays fresh.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/motivation_repository.dart';
import '../data/models/motivation_stats.dart';

part 'motivation_providers.g.dart';

@riverpod
Future<MotivationStats> myMotivationStats(MyMotivationStatsRef ref) {
  return ref.watch(motivationRepositoryProvider).getMyStats();
}
