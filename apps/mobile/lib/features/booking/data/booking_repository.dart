// Story 15.5-mobile — booking-dashboard data access.
//
// Wraps the shipped get_active_holds + get_booking_stats RPCs (migration 0079).
// Scope (leader-subtree / head-all / rep-self) is enforced server-side by
// visible_user_ids() inside the RPCs; this client passes only an optional project
// filter and renders exactly what the RPCs return — it never filters holds itself.
// Hold→sold conversion reuses the shipped confirm_booking seam (see InventoryRepository).

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/active_hold.dart';
import 'models/booking_stats.dart';

part 'booking_repository.g.dart';

/// Raised when a dashboard read is denied. [notAuthenticated] = no session context
/// (`not_authenticated`). An empty scope is NOT an error — the RPC returns zero rows
/// for a rep with no holds / a receptionist, which the UI shows as a calm empty state.
class BookingAccessException implements Exception {
  final String message;
  final bool notAuthenticated;

  const BookingAccessException(this.message, {this.notAuthenticated = false});

  factory BookingAccessException.fromPostgrest(PostgrestException e) {
    if (e.message.contains('not_authenticated')) {
      return BookingAccessException(e.message, notAuthenticated: true);
    }
    return BookingAccessException(e.message);
  }

  String get friendly => notAuthenticated
      ? 'Please sign in again to view the booking dashboard.'
      : "Couldn't load the booking dashboard. Pull to refresh.";

  @override
  String toString() => message;
}

class BookingRepository {
  final SupabaseClient _supabase;

  const BookingRepository(this._supabase);

  /// Active holds in the caller's visibility scope via get_active_holds, ordered
  /// soonest-to-expire first (by the RPC). Optional [projectId] filter.
  Future<List<ActiveHold>> getActiveHolds({String? projectId}) async {
    try {
      final rows = await _supabase.rpc('get_active_holds', params: {
        'p_project_id': projectId,
      });
      return (rows as List)
          .map((r) => ActiveHold.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw BookingAccessException.fromPostgrest(e);
    }
  }

  /// Confirmed bookings + active holds + hold→sold conversion % over [periodDays],
  /// same scope, optional [projectId] and [agentId] filters. [agentId] narrows to a
  /// single holding agent WITHIN the caller's visibility (server-enforced by
  /// visible_user_ids() — an out-of-scope id yields empty, never a leak). Returns
  /// [BookingStats.empty] if the RPC yields no row (defensive).
  Future<BookingStats> getBookingStats({
    int periodDays = 30,
    String? projectId,
    String? agentId,
  }) async {
    try {
      final rows = await _supabase.rpc('get_booking_stats', params: {
        'p_period_days': periodDays,
        'p_project_id': projectId,
        'p_agent_id': agentId,
      });
      final list = rows as List;
      if (list.isEmpty) return BookingStats.empty;
      return BookingStats.fromJson(Map<String, dynamic>.from(list.first as Map));
    } on PostgrestException catch (e) {
      throw BookingAccessException.fromPostgrest(e);
    }
  }
}

@riverpod
BookingRepository bookingRepository(BookingRepositoryRef ref) {
  return BookingRepository(Supabase.instance.client);
}
