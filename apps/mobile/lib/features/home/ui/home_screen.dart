// Story 2.5 — Employee home screen
// UX spec: EXPERIENCE.md §Screens: Today widget (2×2 counts) + urgency-sorted lead list
//   Cold open: skeleton placeholders — no spinner
//   Pull-to-refresh on lead list
//   FAB → showNewLeadSheet() → invalidate myLeadsProvider on success

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../leads/data/lead_repository.dart';
import '../../leads/data/models/lead_model.dart';
import '../../leads/providers/lead_providers.dart';
import '../../leads/ui/lead_card.dart';
import '../../leads/ui/new_lead_sheet.dart';
import '../../leads/ui/filtered_leads_screen.dart';
import '../../leads/ui/followups_screen.dart';
import '../../leads/ui/pending_outcome_sheet.dart';
import '../../motivation/providers/motivation_providers.dart';
import '../../motivation/ui/personal_stats_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  bool _outcomeSheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_outcomeSheetOpen) return;
    _checkPendingOutcomeOnResume();
  }

  Future<void> _checkPendingOutcomeOnResume() async {
    // Refresh leads first — pending_outcome_at was set on a different screen,
    // so the cached provider value is stale until we re-fetch.
    final leads = await ref.refresh(myLeadsProvider.future);
    if (!mounted || _outcomeSheetOpen) return;
    final pending = leads.where((l) => l.hasPendingOutcome).toList()
      ..sort((a, b) => (b.pendingOutcomeAt ?? DateTime(0))
          .compareTo(a.pendingOutcomeAt ?? DateTime(0)));
    if (pending.isEmpty) return;
    _outcomeSheetOpen = true;
    showPendingOutcomeSheet(context, pending.first).whenComplete(() {
      _outcomeSheetOpen = false;
      // A call outcome may change status (incl. → sold) and logs a qualifying action.
      ref.invalidate(myMotivationStatsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final leadsAsync = ref.watch(myLeadsProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: Text(
          'My Leads',
          style: GoogleFonts.sourceSerif4(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: AppColors.inkPrimary,
          ),
        ),
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.event_note_rounded),
            color: AppColors.inkSecondary,
            tooltip: 'Follow-ups calendar',
            onPressed: () => context.push('/followups'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            color: AppColors.inkSecondary,
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myLeadsProvider);
          ref.invalidate(myMotivationStatsProvider);
        },
        color: AppColors.accentStrong,
        backgroundColor: AppColors.surfaceRaised,
        child: leadsAsync.when(
          loading: () => const _SkeletonView(),
          error:   (err, _) => _ErrorView(onRetry: () => ref.invalidate(myLeadsProvider), errorText: err.toString()),
          data:    (leads) => _LeadsView(
            leads: leads,
            onMarkDead: (lead) async {
              try {
                final result = await ref
                    .read(leadRepositoryProvider)
                    .markLeadDead(lead.id);
                ref.invalidate(myLeadsProvider);
                ref.invalidate(myMotivationStatsProvider);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Marked Dead.'),
                    action: SnackBarAction(
                      label: 'Undo',
                      textColor: AppColors.accentStrong,
                      onPressed: () async {
                        await ref
                            .read(leadRepositoryProvider)
                            .restoreLead(lead.id, result.previousStatus);
                        ref.invalidate(myLeadsProvider);
                      },
                    ),
                    duration: const Duration(seconds: 5),
                    backgroundColor: AppColors.surfaceRaised,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not mark lead as dead.')),
                );
              }
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await showNewLeadSheet(context);
          if (created == true) {
            ref.invalidate(myLeadsProvider);
            ref.invalidate(myMotivationStatsProvider);
          }
        },
        backgroundColor: AppColors.accentStrong,
        elevation: 3,
        tooltip: 'New Lead',
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}

// ── Content view ──────────────────────────────────────────────────────────

class _LeadsView extends StatelessWidget {
  final List<LeadListItem> leads;
  final Future<void> Function(LeadListItem)? onMarkDead;
  const _LeadsView({required this.leads, this.onMarkDead});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Today's Actions widget
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _TodayWidget(leads: leads),
          ),
        ),

        // Personal Performance Stats card (Story 7.1) — sits below Today's Actions
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: PersonalStatsCard(),
          ),
        ),

        // Section header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Row(
              children: [
                Text(
                  'MY LEADS',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 11.5 * 0.06,
                    color: AppColors.inkSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunk,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    '${leads.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Empty state
        if (leads.isEmpty)
          const SliverToBoxAdapter(child: _EmptyState()),

        // Lead cards
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final lead = leads[i];
              final card = Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: LeadCard(
                  lead: lead,
                  onTap: () => context.push('/lead/${lead.id}'),
                ),
              );
              if (onMarkDead == null) return card;
              return Dismissible(
                key: ValueKey(lead.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  await onMarkDead!(lead);
                  return true;
                },
                background: const SizedBox.shrink(),
                secondaryBackground: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close_rounded, color: Colors.white, size: 22),
                      SizedBox(height: 2),
                      Text(
                        'Mark Dead',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                child: card,
              );
            },
            childCount: leads.length,
          ),
        ),

        // FAB clearance
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }
}

// ── Today's Actions widget ─────────────────────────────────────────────────

class _TodayWidget extends StatelessWidget {
  final List<LeadListItem> leads;
  const _TodayWidget({required this.leads});

  @override
  Widget build(BuildContext context) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int _sameDay(DateTime? dt) {
      if (dt == null) return 0;
      final l = dt.toLocal();
      return DateTime(l.year, l.month, l.day).isAtSameMomentAs(today) ? 1 : 0;
    }

    final followupsToday = leads.fold(0, (s, l) => s + _sameDay(l.nextFollowupAt));
    final visitsToday    = leads.fold(0, (s, l) => s + _sameDay(l.visitDate));
    final incomplete     = leads.where((l) => l.isIncomplete).length;
    final pendingCalls   = leads.where((l) => l.hasPendingOutcome).length;

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
            "TODAY'S ACTIONS",
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
              _CountTile(
                count: followupsToday,
                label: 'Follow-ups',
                onTap: () => context.push('/leads/filtered', extra: LeadFilter.followupsToday),
              ),
              const SizedBox(width: 8),
              _CountTile(
                count: visitsToday,
                label: 'Visits today',
                onTap: () => context.push('/leads/filtered', extra: LeadFilter.visitsToday),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _CountTile(
                count: incomplete,
                label: 'Incomplete',
                accent: incomplete > 0,
                onTap: () => context.push('/leads/filtered', extra: LeadFilter.incomplete),
              ),
              const SizedBox(width: 8),
              _CountTile(
                count: pendingCalls,
                label: 'Calls pending',
                accent: pendingCalls > 0,
                onTap: () => context.push('/leads/filtered', extra: LeadFilter.pendingOutcome),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  final int count;
  final String label;
  final bool accent;
  final VoidCallback? onTap;

  const _CountTile({
    required this.count,
    required this.label,
    this.accent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final countColor = accent && count > 0
        ? AppColors.statusIncomplete
        : AppColors.inkPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
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
                '$count',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: countColor,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
      child: Column(
        children: [
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(
              color: AppColors.surfaceSunk,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_add_alt_rounded,
              size: 30,
              color: AppColors.inkDisabled,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No active leads',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.inkPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap + to capture your first lead',
            style: TextStyle(fontSize: 14, color: AppColors.inkSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Error state ────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final String? errorText;
  const _ErrorView({required this.onRetry, this.errorText});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load leads',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.inkPrimary,
              ),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                errorText!,
                style: const TextStyle(fontSize: 11, color: AppColors.inkSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: TextStyle(color: AppColors.accentStrong, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton loading view ──────────────────────────────────────────────────

class _SkeletonView extends StatelessWidget {
  const _SkeletonView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Today widget skeleton
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderHairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Shimmer(width: 120, height: 11, radius: 4),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _Shimmer(height: 52, radius: 8)),
                  const SizedBox(width: 8),
                  Expanded(child: _Shimmer(height: 52, radius: 8)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _Shimmer(height: 52, radius: 8)),
                  const SizedBox(width: 8),
                  Expanded(child: _Shimmer(height: 52, radius: 8)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _Shimmer(width: 80, height: 11, radius: 4),
          const SizedBox(height: 12),
          // Skeleton cards
          for (var i = 0; i < 4; i++) ...[
            _SkeletonCard(),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
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
          Row(
            children: [
              Expanded(child: _Shimmer(height: 15, radius: 4)),
              const SizedBox(width: 24),
              _Shimmer(width: 44, height: 22, radius: 9999),
            ],
          ),
          const SizedBox(height: 8),
          _Shimmer(width: 140, height: 13, radius: 4),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _Shimmer(height: 12, radius: 4)),
            const SizedBox(width: 48),
            _Shimmer(width: 40, height: 11, radius: 4),
          ]),
        ],
      ),
    );
  }
}

// Pulsing shimmer box
class _Shimmer extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const _Shimmer({this.width, required this.height, this.radius = 4});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: Color.lerp(
            AppColors.surfaceSunk,
            AppColors.surfaceMist,
            _anim.value,
          ),
        ),
      ),
    );
  }
}
