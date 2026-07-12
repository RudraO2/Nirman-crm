// Story 16.2-mobile — execution-team amendment surface.
//
// Member-gated list of amendments (PII-minimized: unit_no · configuration ·
// description · status — NO lead name/phone) with per-row lifecycle controls via
// set_amendment_status. A non-member sees a calm state; a Builder Head can self-join
// the execution team (add_execution_member). All authority is server-side.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../data/amendments_repository.dart';
import '../data/models/execution_amendment.dart';
import '../providers/amendments_providers.dart';

class AmendmentsExecutionScreen extends ConsumerStatefulWidget {
  const AmendmentsExecutionScreen({super.key});

  @override
  ConsumerState<AmendmentsExecutionScreen> createState() =>
      _AmendmentsExecutionScreenState();
}

class _AmendmentsExecutionScreenState
    extends ConsumerState<AmendmentsExecutionScreen> {
  String _statusFilter = ''; // db value, '' = all
  final Set<String> _advancing = {}; // amendment ids with an in-flight status RPC

  Future<void> _refresh() async {
    try {
      await ref.refresh(amendmentsForExecutionProvider(_statusFilter).future);
    } catch (_) {
      // surfaced via the provider's error state — never throw out of onRefresh
    }
  }

  Future<void> _advance(ExecutionAmendment a, AmendmentStatus to) async {
    // In-flight guard: a double-tap fired the RPC twice — the server's
    // transition validation rejected the second call, but the user got a
    // confusing duplicate error toast (audit medium).
    if (_advancing.contains(a.amendmentId)) return;
    setState(() => _advancing.add(a.amendmentId));
    try {
      await ref.read(amendmentsRepositoryProvider).setAmendmentStatus(
            amendmentId: a.amendmentId,
            newStatus: to,
          );
      if (!mounted) return;
      ref.invalidate(amendmentsForExecutionProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Amendment → ${to.label}')),
      );
    } on ExecutionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.friendly)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update. Try again.")),
      );
    } finally {
      if (mounted) setState(() => _advancing.remove(a.amendmentId));
    }
  }

  Future<void> _joinTeam() async {
    final session = ref.read(authRepositoryProvider).currentSession;
    final uid = session?.user.id;
    if (uid == null) return;
    try {
      await ref.read(amendmentsRepositoryProvider).joinExecutionTeam(uid);
      if (!mounted) return;
      ref.invalidate(amendmentsForExecutionProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added you to the execution team.')),
      );
    } on ExecutionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.friendly)));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.read(authRepositoryProvider).currentSession;
    final isHead = session?.user.appMetadata['role'] == 'admin';
    final amendmentsAsync =
        ref.watch(amendmentsForExecutionProvider(_statusFilter));

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.inkPrimary),
        title: Text(
          'Amendments',
          style: AppType.display(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            color: AppColors.inkPrimary,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.accentStrong,
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _StatusFilter(
              selected: _statusFilter,
              onChanged: (v) => setState(() => _statusFilter = v),
            ),
            const SizedBox(height: 14),
            amendmentsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 44),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accentStrong),
                ),
              ),
              error: (e, _) {
                final ex = e is ExecutionException ? e : null;
                return _NotMemberOrError(
                  message: ex?.friendly ?? "Couldn't load amendments.",
                  showJoin: (ex?.notMember ?? false) && isHead,
                  onJoin: _joinTeam,
                );
              },
              data: (items) {
                if (items.isEmpty) {
                  return const _EmptyState();
                }
                return Column(
                  children: [
                    for (final a in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AmendmentCard(
                          amendment: a,
                          onAdvance: (to) => _advance(a, to),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status filter chips ─────────────────────────────────────────────────────

class _StatusFilter extends StatelessWidget {
  final String selected;
  final void Function(String db) onChanged;
  const _StatusFilter({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip('All', '', selected.isEmpty),
        for (final s in AmendmentStatus.values)
          _chip(s.label, s.dbValue, selected == s.dbValue),
      ],
    );
  }

  Widget _chip(String label, String db, bool active) => GestureDetector(
        onTap: () => onChanged(db),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.evergreen : AppColors.paper,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: active ? AppColors.evergreen : AppColors.borderStrong,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.brassBright : AppColors.inkSecondary,
            ),
          ),
        ),
      );
}

// ── Amendment card ──────────────────────────────────────────────────────────

class _AmendmentCard extends StatelessWidget {
  final ExecutionAmendment amendment;
  final void Function(AmendmentStatus to) onAdvance;
  const _AmendmentCard({required this.amendment, required this.onAdvance});

  @override
  Widget build(BuildContext context) {
    final unitLine = [
      'Unit ${amendment.unitNo}',
      if (amendment.configuration != null && amendment.configuration!.isNotEmpty)
        amendment.configuration!,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  unitLine,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkPrimary,
                  ),
                ),
              ),
              _StatusPill(status: amendment.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            amendment.description,
            style: TextStyle(
                fontSize: 13, color: AppColors.inkSecondary, height: 1.4),
          ),
          if (amendment.status.nextStatuses.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final to in amendment.status.nextStatuses)
                  _ActionChip(
                    label: to == AmendmentStatus.rejected
                        ? 'Reject'
                        : to.label,
                    danger: to == AmendmentStatus.rejected,
                    onTap: () => onAdvance(to),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final bool danger;
  final VoidCallback onTap;
  const _ActionChip({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.accentStrong;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final AmendmentStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _colors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9999)),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  static (Color, Color) _colors(AmendmentStatus s) {
    switch (s) {
      case AmendmentStatus.requested:
        return (AppColors.statusWarm, AppColors.statusWarmBg);
      case AmendmentStatus.acknowledged:
        return (AppColors.statusFuture, AppColors.statusFutureBg);
      case AmendmentStatus.inProgress:
        return (AppColors.accentStrong, AppColors.mist);
      case AmendmentStatus.done:
        return (AppColors.statusSold, AppColors.statusSoldBg);
      case AmendmentStatus.rejected:
        return (AppColors.danger, AppColors.statusHotBg);
    }
  }
}

// ── States ──────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(Icons.build_circle_outlined,
              size: 40, color: AppColors.inkDisabled),
          const SizedBox(height: 12),
          Text('No amendments to show.',
              style: TextStyle(fontSize: 14, color: AppColors.inkSecondary)),
        ],
      ),
    );
  }
}

class _NotMemberOrError extends StatelessWidget {
  final String message;
  final bool showJoin;
  final VoidCallback onJoin;
  const _NotMemberOrError({
    required this.message,
    required this.showJoin,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 8),
      child: Column(
        children: [
          Icon(Icons.groups_outlined, size: 40, color: AppColors.inkDisabled),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.inkSecondary),
          ),
          if (showJoin) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onJoin,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.evergreen,
                side: BorderSide(color: AppColors.evergreen.withValues(alpha: 0.5)),
              ),
              icon: const Icon(Icons.group_add_rounded, size: 18),
              label: const Text('Join execution team'),
            ),
          ],
        ],
      ),
    );
  }
}
