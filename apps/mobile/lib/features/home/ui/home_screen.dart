// Story 2.5 — Employee home screen
// UX spec: EXPERIENCE.md §Screens: Today widget (2×2 counts) + urgency-sorted lead list
//   Cold open: skeleton placeholders — no spinner
//   Pull-to-refresh on lead list
//   FAB → showNewLeadSheet() → invalidate myLeadsProvider on success

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/offline/offline_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../leads/data/lead_repository.dart';
import '../../leads/data/models/lead_model.dart';
import '../../leads/providers/lead_providers.dart';
import '../../leads/ui/lead_card.dart';
import '../../leads/ui/new_lead_sheet.dart';
import '../../leads/ui/filtered_leads_screen.dart';
import '../../leads/ui/pending_outcome_sheet.dart';
import '../../alarms/data/alarm_sync_service.dart';
import '../../motivation/providers/motivation_providers.dart';
import '../../motivation/data/models/motivation_stats.dart';
import '../../motivation/data/models/monthly_best.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  bool _outcomeSheetOpen = false;
  bool _firstReconcile = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Story 10.3 — keep device alarms in sync with the active-lead list.
    // Every follow-up mutation (create / reschedule / complete / status change /
    // reassign) invalidates myLeadsProvider, so a single listener here reconciles
    // alarms for all of them (Task 3). fireImmediately covers the app-open
    // reconcile (Task 4) — correcting drift from server-side changes that
    // happened while the app was closed. Reconcile only on resolved data; pass
    // the loaded leads to avoid a redundant getMyLeads() fetch.
    ref.listenManual<AsyncValue<List<LeadListItem>>>(
      myLeadsProvider,
      (_, next) {
        final leads = next.valueOrNull;
        if (leads == null) return;
        final reason = _firstReconcile ? 'app_open' : 'leads_changed';
        _firstReconcile = false;
        ref.read(alarmSyncServiceProvider).reconcile(reason: reason, leads: leads);
      },
      fireImmediately: true,
    );
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
          // ui-modern-refresh: was sourceSerif4 — the one serif the Fraunces
          // sweep missed. One family everywhere.
          style: AppType.display(fontSize: 21),
        ),
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          const _OfflineBanner(),
          Expanded(
            child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myLeadsProvider);
          ref.invalidate(myMotivationStatsProvider);
          ref.invalidate(myMonthlyBestProvider);
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
                if (!context.mounted) return true;
                ScaffoldMessenger.of(context).showSnackBar(
                  // A3: colors come from the theme's snackBarTheme (dark bar,
                  // ivory text, brass action) — the old white-on-white local
                  // overrides made this unreadable.
                  SnackBar(
                    content: const Text('Marked Dead.'),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () async {
                        await ref
                            .read(leadRepositoryProvider)
                            .restoreLead(lead.id, result.previousStatus);
                        ref.invalidate(myLeadsProvider);
                      },
                    ),
                    duration: const Duration(seconds: 5),
                  ),
                );
                return true;
              } on OfflineQueued {
                // Queued for replay; the cached list already dropped the lead,
                // so dismissing the card is safe. No undo offline (previous
                // status is only known server-side).
                ref.invalidate(myLeadsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Marked Dead — will sync when back online.')),
                  );
                }
                return true;
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not mark lead as dead.')),
                  );
                }
                return false;
              }
            },
          ),
        ),
            ),
          ),
        ],
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

// ── Offline banner ────────────────────────────────────────────────────────
// Amber strip shown while the list is served from the local cache and/or
// offline writes are waiting to replay (Phase 0/1). Hidden when live + drained.

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OfflineBannerState?>(
      valueListenable: OfflineStore.instance.banner,
      builder: (_, state, __) {
        if (state == null) return const SizedBox.shrink();
        final pending = state.pendingActions;
        return Material(
          color: const Color(0xFF7A5A00),
          child: SafeArea(
            bottom: false,
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 15, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pending > 0
                          ? 'Offline — leads from ${_ago(state.syncedAt)} · $pending change${pending == 1 ? '' : 's'} will sync'
                          : 'Offline — showing leads from ${_ago(state.syncedAt)}',
                      style: const TextStyle(fontSize: 12.5, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Content view ──────────────────────────────────────────────────────────

class _LeadsView extends StatelessWidget {
  final List<LeadListItem> leads;
  /// Returns true iff the lead was actually marked dead server-side —
  /// Dismissible only removes the card on success (audit H8).
  final Future<bool> Function(LeadListItem)? onMarkDead;
  const _LeadsView({required this.leads, this.onMarkDead});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Combined dark header card: today counters + progress (§6.3).
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _HomeHeaderCard(leads: leads),
          ),
        ),

        // Section header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  'My Leads',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 10.5 * 0.12,
                    color: AppColors.inkSecondary,
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.mist,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    '${leads.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ),
                const Spacer(),
                // Untouched filter chip — tap to see leads never actioned.
                Builder(builder: (context) {
                  final untouched = leads.where((l) => l.isUntouched).length;
                  if (untouched == 0) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: () => context.push('/leads/filtered',
                        extra: LeadFilter.untouched),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.statusColdBg,
                        borderRadius: BorderRadius.circular(9999),
                        border: Border.all(color: const Color(0xFFC6D6E9)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              size: 11, color: AppColors.statusCold),
                          const SizedBox(width: 4),
                          Text(
                            '$untouched untouched',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.statusCold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
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
                // Only dismiss when the RPC actually succeeded — a failed
                // mark-dead must NOT silently vanish a live lead (audit H8).
                confirmDismiss: (_) => onMarkDead!(lead),
                background: const SizedBox.shrink(),
                secondaryBackground: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(16),
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

// ── Combined header card: today counters + progress (§6.3) ─────────────────

class _HomeHeaderCard extends ConsumerWidget {
  final List<LeadListItem> leads;
  const _HomeHeaderCard({required this.leads});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int sameDay(DateTime? dt) {
      if (dt == null) return 0;
      final l = dt.toLocal();
      return DateTime(l.year, l.month, l.day).isAtSameMomentAs(today) ? 1 : 0;
    }

    final followupsToday = leads.fold(0, (s, l) => s + sameDay(l.nextFollowupAt));
    final visitsToday    = leads.fold(0, (s, l) => s + sameDay(l.visitDate));
    final incomplete     = leads.where((l) => l.isIncomplete).length;
    final pendingCalls   = leads.where((l) => l.hasPendingOutcome).length;

    // Motivation providers — keep the offline/zero fallback (never a red error).
    final stats = ref.watch(myMotivationStatsProvider).maybeWhen(
          data: (s) => s,
          orElse: MotivationStats.zero,
        );
    final best = ref.watch(myMonthlyBestProvider).maybeWhen(
          data: (b) => b,
          orElse: () => MonthlyBest.empty,
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: AppColors.evergreen,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today · ${_eyebrowDate(now)}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 10.5 * 0.12,
              color: const Color(0xFFE9E4D6).withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _HeaderTile(
                count: followupsToday,
                label: 'Follow-ups',
                onTap: () => context.push('/leads/filtered', extra: LeadFilter.followupsToday),
              ),
              const SizedBox(width: 8),
              _HeaderTile(
                count: visitsToday,
                label: 'Visits',
                onTap: () => context.push('/leads/filtered', extra: LeadFilter.visitsToday),
              ),
              const SizedBox(width: 8),
              _HeaderTile(
                count: incomplete,
                label: 'Incomplete',
                alert: incomplete > 0,
                onTap: () => context.push('/leads/filtered', extra: LeadFilter.incomplete),
              ),
              const SizedBox(width: 8),
              _HeaderTile(
                count: pendingCalls,
                label: 'Call pending',
                alert: pendingCalls > 0,
                onTap: () => context.push('/leads/filtered', extra: LeadFilter.pendingOutcome),
              ),
            ],
          ),
          // Progress footer line.
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                    color: const Color(0xFFE9E4D6).withValues(alpha: 0.12)),
              ),
            ),
            child: Row(
              children: [
                _ProgItem(label: 'Sold this month', value: '${stats.soldThisMonth}'),
                _ProgItem(label: 'Streak', value: '${stats.followupStreakDays} days'),
                _BestHint(stats: stats, best: best),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _eyebrowDate(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul',
      'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[dt.weekday - 1]} ${dt.day} ${months[dt.month]}';
  }
}

class _HeaderTile extends StatelessWidget {
  final int count;
  final String label;
  final bool alert;
  final VoidCallback? onTap;

  const _HeaderTile({
    required this.count,
    required this.label,
    this.alert = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final numberColor = alert && count > 0
        ? AppColors.brassBright
        : const Color(0xFFF2EEE2);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFE9E4D6).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFFE9E4D6).withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: AppType.display(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: numberColor,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: const Color(0xFFE9E4D6).withValues(alpha: 0.60),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgItem extends StatelessWidget {
  final String label;
  final String value;
  const _ProgItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label '),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Color(0xFFF2EEE2),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          color: const Color(0xFFE9E4D6).withValues(alpha: 0.60),
        ),
      ),
    );
  }
}

class _BestHint extends StatelessWidget {
  final MotivationStats stats;
  final MonthlyBest best;
  const _BestHint({required this.stats, required this.best});

  @override
  Widget build(BuildContext context) {
    final String text;
    if (best.allTimeBest > 0) {
      final toBeat = best.allTimeBest - best.thisMonthSold + 1;
      text = toBeat <= 0
          ? 'New personal best 🏆'
          : '$toBeat ${toBeat == 1 ? 'sale' : 'sales'} to beat your best 🏆';
    } else {
      text = 'Conversion ${stats.conversionRate.toStringAsFixed(1)}%';
    }
    return Expanded(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.brassBright,
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
