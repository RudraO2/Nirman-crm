// Story 15.5-mobile — booking-dashboard providers.
//
// Families keyed on the optional project filter. Invalidate both after a hold→sold
// conversion so the authoritative refetch reflects the new booking + reduced holds.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/booking_repository.dart';
import '../data/models/active_hold.dart';
import '../data/models/booking_stats.dart';

part 'booking_providers.g.dart';

/// Active holds in the caller's scope, optionally filtered to [projectId]
/// (empty string / null = all projects). Family key is the project id or ''.
@riverpod
Future<List<ActiveHold>> activeHolds(ActiveHoldsRef ref, String projectId) {
  final id = projectId.isEmpty ? null : projectId;
  return ref.watch(bookingRepositoryProvider).getActiveHolds(projectId: id);
}

/// Booking stats for the caller's scope, optionally filtered to [projectId] and
/// [agentId] (empty string = no filter). Family key is (projectId, agentId).
@riverpod
Future<BookingStats> bookingStats(
  BookingStatsRef ref,
  String projectId,
  String agentId,
) {
  final pid = projectId.isEmpty ? null : projectId;
  final aid = agentId.isEmpty ? null : agentId;
  return ref
      .watch(bookingRepositoryProvider)
      .getBookingStats(projectId: pid, agentId: aid);
}
