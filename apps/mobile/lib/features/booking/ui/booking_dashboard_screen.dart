// Story 15.5-mobile — booking dashboard.
//
// Head/leader view of active holds (live countdown) + booking conversion stats,
// scoped server-side by visible_user_ids(). A hold can be converted to a booking in
// place via the reused confirm_booking seam (payment-verified attestation → hold→sold
// + the FR-34 celebration). Countdown widget + confirm dialog are reused from Slice 1.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/ui/confirm_booking_dialog.dart';
import '../../inventory/ui/hold_countdown.dart';
import '../../amendments/ui/log_amendment_sheet.dart';
import '../../leads/providers/lead_providers.dart';
import '../data/booking_repository.dart';
import '../data/models/active_hold.dart';
import '../data/models/booking_stats.dart';
import '../providers/booking_providers.dart';

class BookingDashboardScreen extends ConsumerStatefulWidget {
  const BookingDashboardScreen({super.key});

  @override
  ConsumerState<BookingDashboardScreen> createState() =>
      _BookingDashboardScreenState();
}

class _BookingDashboardScreenState
    extends ConsumerState<BookingDashboardScreen> {
  // '' = all projects. Family key for both providers.
  String _projectFilter = '';

  Future<void> _refresh() async {
    try {
      await Future.wait([
        ref.refresh(activeHoldsProvider(_projectFilter).future),
        ref.refresh(bookingStatsProvider(_projectFilter).future),
      ]);
    } catch (_) {
      // A refetch error surfaces via the providers' error state — never let it
      // throw out of the RefreshIndicator callback (Slice 2 review finding).
    }
  }

  Future<void> _convert(ActiveHold hold) async {
    final ok = await showConfirmBookingDialog(context, hold.unitNo);
    if (!ok || !mounted) return;
    try {
      await ref.read(inventoryRepositoryProvider).confirmBooking(hold.holdId);
      if (!mounted) return;
      ref.invalidate(activeHoldsProvider);
      ref.invalidate(bookingStatsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unit ${hold.unitNo} booked — marked Sold.')),
      );
    } on ConfirmException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_confirmMessage(e))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't confirm the booking. Try again.")),
      );
    }
  }

  Future<void> _logAmendment(ActiveHold hold) async {
    final logged = await showLogAmendmentSheet(
      context,
      unitId: hold.unitId,
      leadId: hold.leadId,
      unitNo: hold.unitNo,
      leadLabel: hold.leadLabel,
    );
    if (logged == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Amendment logged for unit ${hold.unitNo}.')),
      );
    }
  }

  static String _confirmMessage(ConfirmException e) {
    if (e.notAllowed) {
      return 'Only a Builder Head or Team Leader can confirm a booking.';
    }
    if (e.stale) return 'This hold just changed — pull to refresh and retry.';
    if (e.paymentNotVerified) return 'Payment must be verified first.';
    return "Couldn't confirm the booking. Try again.";
  }

  @override
  Widget build(BuildContext context) {
    final holdsAsync = ref.watch(activeHoldsProvider(_projectFilter));
    final statsAsync = ref.watch(bookingStatsProvider(_projectFilter));

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.inkPrimary),
        title: Text(
          'Booking dashboard',
          style: GoogleFonts.fraunces(
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
            _StatsHeader(stats: statsAsync.valueOrNull ?? BookingStats.empty),
            const SizedBox(height: 16),
            _ProjectFilter(
              selected: _projectFilter,
              onChanged: (id) => setState(() => _projectFilter = id),
            ),
            const SizedBox(height: 16),
            Text(
              'ACTIVE HOLDS',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.26,
                color: AppColors.inkSecondary,
              ),
            ),
            const SizedBox(height: 8),
            holdsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accentStrong),
                ),
              ),
              error: (e, _) => _ErrorState(
                message: e is BookingAccessException
                    ? e.friendly
                    : "Couldn't load holds. Pull to refresh.",
              ),
              data: (holds) {
                if (holds.isEmpty) return const _EmptyState();
                return Column(
                  children: [
                    for (final h in holds)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _HoldCard(
                          hold: h,
                          onConvert: () => _convert(h),
                          onLogAmendment: () => _logAmendment(h),
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

// ── Stats header (3 tiles) ──────────────────────────────────────────────────

class _StatsHeader extends StatelessWidget {
  final BookingStats stats;
  const _StatsHeader({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Confirmed',
            value: '${stats.confirmedBookings}',
            color: AppColors.statusSold,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Active holds',
            value: '${stats.activeHolds}',
            color: AppColors.statusWarm,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Conversion',
            value: stats.conversionLabel,
            color: AppColors.accentStrong,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.fraunces(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Project filter chips ────────────────────────────────────────────────────

class _ProjectFilter extends ConsumerWidget {
  final String selected;
  final void Function(String id) onChanged;
  const _ProjectFilter({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(availableProjectsProvider);
    return projectsAsync.maybeWhen(
      data: (projects) {
        if (projects.isEmpty) return const SizedBox.shrink();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChip(
              label: 'All projects',
              active: selected.isEmpty,
              onTap: () => onChanged(''),
            ),
            for (final p in projects)
              _FilterChip(
                label: p.name,
                active: selected == p.id,
                onTap: () => onChanged(p.id),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: active ? AppColors.brassBright : AppColors.inkSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Hold card ───────────────────────────────────────────────────────────────

class _HoldCard extends StatelessWidget {
  final ActiveHold hold;
  final VoidCallback onConvert;
  final VoidCallback onLogAmendment;
  const _HoldCard({
    required this.hold,
    required this.onConvert,
    required this.onLogAmendment,
  });

  @override
  Widget build(BuildContext context) {
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
                  'Unit ${hold.unitNo}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkPrimary,
                  ),
                ),
              ),
              HoldCountdown(expiresAt: hold.expiresAt, compact: true),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${hold.leadLabel} · ${hold.agentLabel}',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSecondary),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: onLogAmendment,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.inkSecondary,
                      side: BorderSide(color: AppColors.borderStrong),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    icon: const Icon(Icons.build_circle_outlined, size: 17),
                    label: const Text('Amendment',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: onConvert,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.statusSold,
                      side: BorderSide(
                          color: AppColors.statusSold.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    icon: const Icon(Icons.verified_rounded, size: 17),
                    label: const Text('Convert to sold',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
          Icon(Icons.event_available_rounded,
              size: 40, color: AppColors.inkDisabled),
          const SizedBox(height: 12),
          Text(
            'No active holds right now.',
            style: TextStyle(fontSize: 14, color: AppColors.inkSecondary),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.inkSecondary),
        ),
      ),
    );
  }
}
