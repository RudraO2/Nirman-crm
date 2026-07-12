// The head's home — VISUAL insights (redesign #3, 2026-07-13).
//
// Rudra's brief: modern, meaningful, minimalist; same fonts/palette; no
// clutter, no cheap stat boxes. Composition:
//
//   1. MOMENTUM  — 14-day new-leads bar chart (the visual anchor), headline
//                  number = today, brass bar = today, quiet evergreen bars
//                  for history. Real chart, no library, no chart junk.
//   2. PIPELINE  — every lead right now as ONE stacked band, sliced with the
//                  app's existing status colors + a compact legend. The whole
//                  book in one line.
//   3. PULSE     — three quiet inline stats (missed follow-ups · sold this
//                  month · active today). Numbers only get color when they
//                  mean something.
//   4. TEAM      — one card, divider-separated rows (not N bordered boxes).
//
// Data = RPCs the web dashboard already uses; nothing new server-side.

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
    final pipelineAsync = ref.watch(pipeline14dProvider);
    final statusAsync = ref.watch(statusDistributionProvider);

    final team = activityAsync.valueOrNull;
    final activeToday = team
        ?.where((r) => r.leadsUpdatedToday > 0 || r.followupsCompletedToday > 0)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1 · Momentum ────────────────────────────────────────────────
        pipelineAsync.when(
          loading: () => const _Skeleton(height: 168),
          error: (_, __) => const _QuietNote('Chart unavailable — pull to refresh.'),
          data: (days) => _MomentumCard(days: days),
        ),
        const SizedBox(height: 12),

        // ── 2 · Pipeline band ───────────────────────────────────────────
        statusAsync.when(
          loading: () => const _Skeleton(height: 120),
          error: (_, __) => const SizedBox.shrink(),
          data: (dist) => _PipelineBand(dist: dist),
        ),

        // ── 3 · Pulse strip ─────────────────────────────────────────────
        metricsAsync.maybeWhen(
          data: (m) => Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 0),
            child: Row(
              children: [
                _Pulse(
                  value: '${m.followupsMissedToday}',
                  label: 'missed follow-ups',
                  alert: m.followupsMissedToday > 0,
                ),
                _PulseDot(),
                _Pulse(value: '${m.soldThisMonth}', label: 'sold this month'),
                if (activeToday != null) ...[
                  _PulseDot(),
                  _Pulse(
                    value: '$activeToday/${team!.length}',
                    label: 'active today',
                  ),
                ],
              ],
            ),
          ),
          orElse: () => const SizedBox.shrink(),
        ),

        // ── 4 · Team ────────────────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 26, 0, 10),
          child: Text(
            'TEAM',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.26,
              color: AppColors.inkSecondary,
            ),
          ),
        ),
        activityAsync.when(
          loading: () => const _Skeleton(height: 120),
          error: (_, __) =>
              const _QuietNote('Team activity unavailable — pull to refresh.'),
          data: (rows) => rows.isEmpty
              ? const _QuietNote(
                  'No employees yet. Invite your team from the web dashboard.')
              : _TeamCard(rows: rows),
        ),
      ],
    );
  }
}

// ── 1 · Momentum: 14-day new-leads bars ─────────────────────────────────────

class _MomentumCard extends StatelessWidget {
  final List<PipelineDay> days;
  const _MomentumCard({required this.days});

  @override
  Widget build(BuildContext context) {
    final today = days.isEmpty ? 0 : days.last.newLeads;
    final total = days.fold<int>(0, (s, d) => s + d.newLeads);
    final maxV =
        days.fold<int>(0, (s, d) => d.newLeads > s ? d.newLeads : s);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$today', style: AppType.display(fontSize: 40)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'new leads today',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '$total in 14 days',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.inkDisabled),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: _Bar(
                      // Zero-lead days keep a 3px stub so the axis stays legible.
                      heightFactor:
                          maxV == 0 ? 0 : days[i].newLeads / maxV,
                      isToday: i == days.length - 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_dayLabel(days.isEmpty ? null : days.first.day),
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.inkDisabled)),
              const Text('today',
                  style:
                      TextStyle(fontSize: 10.5, color: AppColors.inkDisabled)),
            ],
          ),
        ],
      ),
    );
  }

  static String _dayLabel(DateTime? d) {
    if (d == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

class _Bar extends StatelessWidget {
  final double heightFactor;
  final bool isToday;
  const _Bar({required this.heightFactor, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final h = 3.0 + heightFactor * 61.0;
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: isToday
            ? AppColors.brass
            : AppColors.evergreen.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ── 2 · Pipeline: one stacked band of the whole book ───────────────────────

class _PipelineBand extends StatelessWidget {
  final List<StatusCount> dist;
  const _PipelineBand({required this.dist});

  static const _order = ['hot', 'warm', 'cold', 'future', 'sold', 'dead'];

  @override
  Widget build(BuildContext context) {
    final byStatus = {for (final s in dist) s.status: s.count};
    final slices = [
      for (final s in _order)
        if ((byStatus[s] ?? 0) > 0) StatusCount(s, byStatus[s]!)
    ];
    final total = slices.fold<int>(0, (a, s) => a + s.count);
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Pipeline', style: AppType.display(fontSize: 16)),
              const Spacer(),
              Text(
                '$total leads',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.inkDisabled),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (var i = 0; i < slices.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: slices[i].count,
                      child: Container(color: slices[i].status.statusColor),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final s in slices)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: s.status.statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${s.status.statusLabel} ${s.count}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 3 · Pulse: inline stats, no boxes ───────────────────────────────────────

class _Pulse extends StatelessWidget {
  final String value;
  final String label;
  final bool alert;
  const _Pulse({required this.value, required this.label, this.alert = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: AppType.display(
            fontSize: 17,
            color: alert ? AppColors.statusWarm : AppColors.inkPrimary,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.inkSecondary,
          ),
        ),
      ],
    );
  }
}

class _PulseDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 9),
        child: Text('·',
            style: TextStyle(fontSize: 14, color: AppColors.inkDisabled)),
      );
}

// ── 4 · Team: one card, divided rows ────────────────────────────────────────

class _TeamCard extends StatelessWidget {
  final List<TeamActivityRow> rows;
  const _TeamCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                  height: 1, thickness: 1, color: AppColors.line, indent: 64),
            _ActivityRow(row: rows[i]),
          ],
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.brassSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Color(0xFF6E5423),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
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
                const SizedBox(height: 1),
                Text(
                  '${row.leadsUpdatedToday} updated · '
                  '${row.followupsCompletedToday} follow-ups today',
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
              color: idleLong ? AppColors.statusWarm : AppColors.inkDisabled,
            ),
          ),
        ],
      ),
    );
  }
}

// ── shared ──────────────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  final double height;
  const _Skeleton({required this.height});
  @override
  Widget build(BuildContext context) => Container(
        height: height,
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
