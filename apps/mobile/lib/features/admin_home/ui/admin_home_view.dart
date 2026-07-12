// The head's home — numbers first (eyeball feedback 2026-07-12, redesigned
// 2026-07-13 after Rudra's "green bar looks weird" review).
//
// One calm surface: a single 2×2 pulse grid on paper, hairline-divided, that
// answers the boss's four morning questions — leads coming in? follow-ups
// slipping? sales closing? team working? Typography carries the hierarchy
// (big ink numbers, small labels); color appears ONLY as signal (amber when
// follow-ups are slipping / someone's idle, green when growing). Below it,
// the team activity list is the only other element on the screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/admin_home_repository.dart';

class AdminHomeView extends ConsumerWidget {
  const AdminHomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(adminHomeMetricsProvider);
    final activityAsync = ref.watch(teamActivityProvider);

    final team = activityAsync.valueOrNull;
    final activeToday = team == null
        ? null
        : team
            .where((r) =>
                r.leadsUpdatedToday > 0 || r.followupsCompletedToday > 0)
            .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        metricsAsync.when(
          loading: () => const _PulseSkeleton(),
          error: (_, __) =>
              const _QuietNote('Numbers unavailable — pull to refresh.'),
          data: (m) => _PulseGrid(
            m: m,
            activeToday: activeToday,
            teamSize: team?.length,
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 24, 0, 10),
          child: Text(
            'TEAM ACTIVITY',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.26,
              color: AppColors.inkSecondary,
            ),
          ),
        ),
        activityAsync.when(
          loading: () => const _QuietNote('Loading team…'),
          error: (_, __) =>
              const _QuietNote('Team activity unavailable — pull to refresh.'),
          data: (rows) => rows.isEmpty
              ? const _QuietNote(
                  'No employees yet. Invite your team from the web dashboard.')
              : Column(
                  children: [for (final r in rows) _ActivityRow(row: r)],
                ),
        ),
      ],
    );
  }
}

/// 2×2 pulse: new today · missed follow-ups / sold this month · team active.
class _PulseGrid extends StatelessWidget {
  final AdminHomeMetrics m;
  final int? activeToday;
  final int? teamSize;
  const _PulseGrid({required this.m, this.activeToday, this.teamSize});

  @override
  Widget build(BuildContext context) {
    final delta = m.leadsToday - m.leadsYesterday;
    final soldDelta = m.soldThisMonth - m.soldLastMonth;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                _Cell(
                  value: '${m.leadsToday}',
                  label: 'New leads today',
                  caption: delta == 0
                      ? 'same as yesterday'
                      : '${delta > 0 ? '+' : ''}$delta vs yesterday',
                  captionColor:
                      delta > 0 ? AppColors.statusSold : AppColors.inkDisabled,
                ),
                const _VDivider(),
                _Cell(
                  value: '${m.followupsMissedToday}',
                  label: 'Missed follow-ups',
                  caption: m.followupsMissedToday > 0
                      ? 'needs a nudge'
                      : 'all on time',
                  valueColor: m.followupsMissedToday > 0
                      ? AppColors.statusWarm
                      : AppColors.inkPrimary,
                  captionColor: m.followupsMissedToday > 0
                      ? AppColors.statusWarm
                      : AppColors.inkDisabled,
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          IntrinsicHeight(
            child: Row(
              children: [
                _Cell(
                  value: '${m.soldThisMonth}',
                  label: 'Sold this month',
                  caption: soldDelta == 0
                      ? 'last month ${m.soldLastMonth}'
                      : '${soldDelta > 0 ? '+' : ''}$soldDelta vs last month',
                  captionColor: soldDelta > 0
                      ? AppColors.statusSold
                      : AppColors.inkDisabled,
                ),
                const _VDivider(),
                _Cell(
                  value: activeToday == null ? '—' : '$activeToday',
                  label: 'Active today',
                  caption: teamSize == null
                      ? '' // still loading — keep quiet
                      : 'of $teamSize on the team',
                  captionColor: AppColors.inkDisabled,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String value;
  final String label;
  final String caption;
  final Color valueColor;
  final Color captionColor;

  const _Cell({
    required this.value,
    required this.label,
    required this.caption,
    this.valueColor = AppColors.inkPrimary,
    this.captionColor = AppColors.inkDisabled,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AppType.display(fontSize: 30, color: valueColor)),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSecondary,
              ),
            ),
            if (caption.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(
                caption,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: captionColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();
  @override
  Widget build(BuildContext context) =>
      const VerticalDivider(width: 1, thickness: 1, color: AppColors.line);
}

class _ActivityRow extends StatelessWidget {
  final TeamActivityRow row;
  const _ActivityRow({required this.row});

  static String _relative(DateTime? dt) {
    if (dt == null) return 'no activity yet';
    final d = DateTime.now().difference(dt.toLocal());
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final name = row.employeeName.contains('@')
        ? row.employeeName.split('@').first
        : row.employeeName;
    final initial = name.isEmpty ? '·' : name[0].toUpperCase();
    final idleLong = row.lastActionAt == null ||
        DateTime.now().difference(row.lastActionAt!.toLocal()).inHours >= 24;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.brassSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Color(0xFF6E5423),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${row.leadsUpdatedToday} updated today · '
                    '${row.followupsCompletedToday} follow-ups done',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.inkSecondary),
                  ),
                ],
              ),
            ),
            Text(
              _relative(row.lastActionAt),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: idleLong ? AppColors.statusWarm : AppColors.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseSkeleton extends StatelessWidget {
  const _PulseSkeleton();
  @override
  Widget build(BuildContext context) => Container(
        height: 176,
        decoration: BoxDecoration(
          color: AppColors.mist,
          borderRadius: BorderRadius.circular(18),
        ),
      );
}

class _QuietNote extends StatelessWidget {
  final String text;
  const _QuietNote(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary),
        ),
      );
}
