// Eyeball feedback (2026-07-12) — the head's mobile home.
//
// A builder head who assigns everything to reps opened the app to an EMPTY
// "My Leads" and an empty Plan tab; his real tools hid inside You. His home
// should BE the numbers. Wraps the two admin stats RPCs the web dashboard
// already uses: get_builder_home_metrics (0048/0116) and
// get_employee_activity_stats (0051/0116). Both are admin-only server-side
// (ERRCODE 42501) — this surface is only routed for role == 'admin'.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'admin_home_repository.g.dart';

class AdminHomeMetrics {
  final int leadsToday;
  final int leadsYesterday;
  final int followupsMissedToday;
  final int followupsMissedYesterday;
  final int soldThisMonth;
  final int soldLastMonth;

  const AdminHomeMetrics({
    required this.leadsToday,
    required this.leadsYesterday,
    required this.followupsMissedToday,
    required this.followupsMissedYesterday,
    required this.soldThisMonth,
    required this.soldLastMonth,
  });

  factory AdminHomeMetrics.fromJson(Map<String, dynamic> j) => AdminHomeMetrics(
        leadsToday: (j['leads_today'] as num?)?.toInt() ?? 0,
        leadsYesterday: (j['leads_yesterday'] as num?)?.toInt() ?? 0,
        followupsMissedToday:
            (j['followups_missed_today'] as num?)?.toInt() ?? 0,
        followupsMissedYesterday:
            (j['followups_missed_yesterday'] as num?)?.toInt() ?? 0,
        soldThisMonth: (j['sold_this_month'] as num?)?.toInt() ?? 0,
        soldLastMonth: (j['sold_last_month'] as num?)?.toInt() ?? 0,
      );
}

class TeamActivityRow {
  final String employeeId;
  final String employeeName;
  final DateTime? lastActionAt;
  final int leadsUpdatedToday;
  final int followupsCompletedToday;

  const TeamActivityRow({
    required this.employeeId,
    required this.employeeName,
    required this.lastActionAt,
    required this.leadsUpdatedToday,
    required this.followupsCompletedToday,
  });

  factory TeamActivityRow.fromJson(Map<String, dynamic> j) => TeamActivityRow(
        employeeId: j['employee_id'] as String,
        employeeName: (j['employee_name'] as String?) ?? '—',
        lastActionAt: j['last_action_at'] == null
            ? null
            : DateTime.tryParse(j['last_action_at'] as String),
        leadsUpdatedToday: (j['leads_updated_today'] as num?)?.toInt() ?? 0,
        followupsCompletedToday:
            (j['followups_completed_today'] as num?)?.toInt() ?? 0,
      );
}

class AdminHomeRepository {
  final SupabaseClient _supabase;
  const AdminHomeRepository(this._supabase);

  Future<AdminHomeMetrics> getHomeMetrics() async {
    final rows = await _supabase.rpc('get_builder_home_metrics');
    final list = rows as List;
    if (list.isEmpty) {
      return const AdminHomeMetrics(
        leadsToday: 0,
        leadsYesterday: 0,
        followupsMissedToday: 0,
        followupsMissedYesterday: 0,
        soldThisMonth: 0,
        soldLastMonth: 0,
      );
    }
    return AdminHomeMetrics.fromJson(
        Map<String, dynamic>.from(list.first as Map));
  }

  Future<List<TeamActivityRow>> getTeamActivity() async {
    final rows = await _supabase.rpc('get_employee_activity_stats');
    return (rows as List)
        .map((r) =>
            TeamActivityRow.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}

@riverpod
AdminHomeRepository adminHomeRepository(AdminHomeRepositoryRef ref) {
  return AdminHomeRepository(Supabase.instance.client);
}

@riverpod
Future<AdminHomeMetrics> adminHomeMetrics(AdminHomeMetricsRef ref) {
  return ref.watch(adminHomeRepositoryProvider).getHomeMetrics();
}

@riverpod
Future<List<TeamActivityRow>> teamActivity(TeamActivityRef ref) {
  return ref.watch(adminHomeRepositoryProvider).getTeamActivity();
}
