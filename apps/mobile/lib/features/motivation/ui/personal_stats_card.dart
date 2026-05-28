// Story 7.1 — Personal Performance Stats card.
// Sits below the Today's Actions widget on the Employee home (AC-1).
// Shows Sold this month / Follow-up streak / Conversion rate, caller-only.
// Offline/error → last-cached values with "Updated …" subtitle, never a red error (AC-6).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/motivation_stats.dart';
import '../providers/motivation_providers.dart';

class PersonalStatsCard extends ConsumerWidget {
  const PersonalStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(myMotivationStatsProvider);
    return statsAsync.when(
      loading: () => const _StatsShell(child: _StatsSkeleton()),
      // No cache available and fetch failed → show zeros, not an error state.
      error: (_, __) => _StatsShell(child: _StatsContent(stats: MotivationStats.zero())),
      data: (stats) => _StatsShell(child: _StatsContent(stats: stats)),
    );
  }
}

class _StatsShell extends StatelessWidget {
  final Widget child;
  const _StatsShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderHairline),
      ),
      child: child,
    );
  }
}

class _StatsContent extends StatelessWidget {
  final MotivationStats stats;
  const _StatsContent({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MY PROGRESS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 11.0 * 0.08,
            color: AppColors.inkSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _StatTile(value: '${stats.soldThisMonth}', label: 'Sold this month'),
            const SizedBox(width: 8),
            _StatTile(
              value: '${stats.followupStreakDays}',
              label: 'Day streak',
            ),
            const SizedBox(width: 8),
            _StatTile(
              value: '${stats.conversionRate.toStringAsFixed(1)}%',
              label: 'Conversion',
            ),
          ],
        ),
        if (_subtitle(stats.fetchedAt) != null) ...[
          const SizedBox(height: 10),
          Text(
            _subtitle(stats.fetchedAt)!,
            style: const TextStyle(fontSize: 10.5, color: AppColors.inkSecondary),
          ),
        ],
      ],
    );
  }

  // Shows "Updated …" when the snapshot is not brand-new (i.e. cached) (AC-6).
  // Epoch sentinel (0) means "no real timestamp" — hide the subtitle.
  static String? _subtitle(DateTime fetchedAt) {
    if (fetchedAt.millisecondsSinceEpoch == 0) return null;
    final age = DateTime.now().difference(fetchedAt);
    if (age.inSeconds < 30) return null; // fresh fetch — no subtitle
    if (age.inMinutes < 1) return 'Updated just now';
    if (age.inMinutes < 60) return 'Updated ${age.inMinutes}m ago';
    if (age.inHours < 24) return 'Updated ${age.inHours}h ago';
    return 'Updated ${age.inDays}d ago';
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  const _StatTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceBase,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.inkPrimary,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: AppColors.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget tile() => Expanded(
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceBase,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 110,
          height: 11,
          decoration: BoxDecoration(
            color: AppColors.surfaceSunk,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [tile(), const SizedBox(width: 8), tile(), const SizedBox(width: 8), tile()],
        ),
      ],
    );
  }
}
