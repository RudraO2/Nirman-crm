// Story 7.4 — Monthly personal-best UI.
// - PreviousMonthCard: shown only in the first 7 days of the month (last month vs all-time best).
// - NewPersonalBestBanner: shown when this month beats the prior best; dismissible per month.
// Both are personal only — no comparison to other employees (AC-4).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/monthly_best.dart';
import '../providers/motivation_providers.dart';

String _currentMonthKey() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}';
}

/// Renders the previous-month card and/or the new-best banner based on the RPC.
class MonthlyBestSection extends ConsumerStatefulWidget {
  const MonthlyBestSection({super.key});

  @override
  ConsumerState<MonthlyBestSection> createState() => _MonthlyBestSectionState();
}

class _MonthlyBestSectionState extends ConsumerState<MonthlyBestSection> {
  static const _storage = FlutterSecureStorage();
  static const _dismissKey = 'monthly_best_dismissed';
  bool _dismissedThisMonth = false;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    final v = await _storage.read(key: _dismissKey);
    if (mounted && v == _currentMonthKey()) {
      setState(() => _dismissedThisMonth = true);
    }
  }

  Future<void> _dismiss() async {
    await _storage.write(key: _dismissKey, value: _currentMonthKey());
    if (mounted) setState(() => _dismissedThisMonth = true);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myMonthlyBestProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (mb) {
        final children = <Widget>[];
        if (mb.isNewBest && !_dismissedThisMonth) {
          children.add(_NewBestBanner(count: mb.thisMonthSold, onDismiss: _dismiss));
        }
        if (mb.showPreviousMonthCard) {
          children.add(_PreviousMonthCard(lastMonth: mb.lastMonthSold, best: mb.allTimeBest));
        }
        if (children.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                children[i],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NewBestBanner extends StatelessWidget {
  final int count;
  final VoidCallback onDismiss;
  const _NewBestBanner({required this.count, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.accentStrong.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentStrong.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'New personal best — $count closed this month!',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.accentStrong,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.inkSecondary,
            tooltip: 'Dismiss',
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _PreviousMonthCard extends StatelessWidget {
  final int lastMonth;
  final int best;
  const _PreviousMonthCard({required this.lastMonth, required this.best});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PREVIOUS MONTH',
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
              _Metric(value: '$lastMonth', label: 'Closed last month'),
              const SizedBox(width: 8),
              _Metric(value: '$best', label: 'All-time best month'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  const _Metric({required this.value, required this.label});

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
            Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.inkSecondary)),
          ],
        ),
      ),
    );
  }
}
