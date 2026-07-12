// The head's home — numbers first (eyeball feedback 2026-07-12).
//
// Rendered by HomeScreen when role == 'admin' instead of the rep lead list.
// Three blocks: today's pulse (evergreen card), sold month tiles, and the
// team activity list — the same truths the web dashboard shows, sized for a
// phone glance. The head's own leads (if any) render below via the parent.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/admin_home_repository.dart';

const _ivory = Color(0xFFF2EEE2);
const _ivoryFaint = Color(0xFFE9E4D6);

class AdminHomeView extends ConsumerWidget {
  const AdminHomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(adminHomeMetricsProvider);
    final activityAsync = ref.watch(teamActivityProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        metricsAsync.when(
          loading: () => const _MetricsSkeleton(),
          error: (_, __) => const _QuietError('Numbers unavailable — pull to refresh.'),
          data: (m) => _TodayCard(m: m),
        ),
        const SizedBox(height: 12),
        metricsAsync.maybeWhen(
          data: (m) => _SoldRow(m: m),
          orElse: () => const SizedBox.shrink(),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(0, 22, 0, 8),
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
          loading: () => const _QuietError('Loading team…'),
          error: (_, __) => const _QuietError('Team activity unavailable — pull to refresh.'),
          data: (rows) => rows.isEmpty
              ? const _QuietError(
                  'No employees yet. Invite your team from the web dashboard.')
              : Column(
                  children: [for (final r in rows) _ActivityRow(row: r)],
                ),
        ),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  final AdminHomeMetrics m;
  const _TodayCard({required this.m});

  @override
  Widget build(BuildContext context) {
    final delta = m.leadsToday - m.leadsYesterday;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.evergreen,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New leads today',
                  style: TextStyle(
                      fontSize: 12, color: _ivoryFaint.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${m.leadsToday}',
                      style: AppType.display(fontSize: 34, color: _ivory),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        delta == 0
                            ? 'same as yesterday'
                            : delta > 0
                                ? '+$delta vs yesterday'
                                : '$delta vs yesterday',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: delta >= 0
                              ? AppColors.brassBright
                              : _ivoryFaint.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(width: 1, height: 44, color: _ivoryFaint.withValues(alpha: 0.15)),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Missed follow-ups',
                style: TextStyle(
                    fontSize: 12, color: _ivoryFaint.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 4),
              Text(
                '${m.followupsMissedToday}',
                style: AppType.display(
                  fontSize: 34,
                  color: m.followupsMissedToday > 0
                      ? const Color(0xFFE8A196)
                      : _ivory,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SoldRow extends StatelessWidget {
  final AdminHomeMetrics m;
  const _SoldRow({required this.m});

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, int value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.inkSecondary)),
                const SizedBox(height: 2),
                Text('$value', style: AppType.display(fontSize: 24)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        tile('Sold this month', m.soldThisMonth),
        const SizedBox(width: 10),
        tile('Sold last month', m.soldLastMonth),
      ],
    );
  }
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
                color: idleLong
                    ? AppColors.statusWarm
                    : AppColors.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsSkeleton extends StatelessWidget {
  const _MetricsSkeleton();
  @override
  Widget build(BuildContext context) => Container(
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.mist,
          borderRadius: BorderRadius.circular(18),
        ),
      );
}

class _QuietError extends StatelessWidget {
  final String text;
  const _QuietError(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary),
        ),
      );
}
