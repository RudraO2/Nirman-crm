// Story 14.3-mobile + 15.2-mobile — unit detail sheet.
//
// 14.3: read-only detail (margin row head-only). 15.2: for an `available` unit the
// Hold button is live → pick one of your leads → hold_unit CAS → the grid tile flips
// amber via the existing Realtime refetch (no optimistic client lie). For a `hold`
// unit it shows the live countdown to expires_at (read from unit_holds).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/inventory_repository.dart';
import '../data/models/unit_hold_model.dart';
import '../data/models/unit_model.dart';
import '../providers/inventory_providers.dart';
import 'confirm_booking_dialog.dart';
import 'hold_countdown.dart';
import 'hold_lead_picker_sheet.dart';
import 'unit_status_style.dart';

class UnitDetailSheet extends ConsumerStatefulWidget {
  final ProjectUnit unit;
  final String projectId;

  const UnitDetailSheet({
    super.key,
    required this.unit,
    required this.projectId,
  });

  static Future<void> show(
    BuildContext context,
    ProjectUnit unit,
    String projectId,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => UnitDetailSheet(unit: unit, projectId: projectId),
    );
  }

  @override
  ConsumerState<UnitDetailSheet> createState() => _UnitDetailSheetState();
}

class _UnitDetailSheetState extends ConsumerState<UnitDetailSheet> {
  bool _holding = false;
  bool _confirming = false;

  ProjectUnit get unit => widget.unit;

  Future<void> _startConfirm(String holdId) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final ok = await showConfirmBookingDialog(context, unit.unitNo);
    if (!ok || !mounted) return;

    setState(() => _confirming = true);
    try {
      await ref.read(inventoryRepositoryProvider).confirmBooking(holdId);
      ref.invalidate(projectUnitsProvider(widget.projectId));
      ref.invalidate(activeHoldProvider(unit.unitId));
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Booked! 🎉 Unit ${unit.unitNo} sold')),
      );
    } on ConfirmException catch (e) {
      if (!mounted) return;
      setState(() => _confirming = false);
      if (e.notAllowed) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Only a manager can confirm a booking.')),
        );
      } else if (e.stale) {
        ref.invalidate(projectUnitsProvider(widget.projectId));
        messenger.showSnackBar(
          const SnackBar(
              content: Text('This hold is no longer active — refreshing.')),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not confirm the booking. Try again.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _confirming = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not confirm the booking. Try again.')),
      );
    }
  }

  Future<void> _startHold() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final lead = await showHoldLeadPicker(context);
    if (lead == null || !mounted) return;

    setState(() => _holding = true);
    try {
      final hold =
          await ref.read(inventoryRepositoryProvider).holdUnit(unit.unitId, lead.id);
      // Authoritative refresh — the tile flips amber from the refetch, not a guess.
      ref.invalidate(projectUnitsProvider(widget.projectId));
      ref.invalidate(activeHoldProvider(unit.unitId));
      navigator.pop(); // close the detail sheet
      final left = formatRemaining(hold.expiresAt.difference(DateTime.now()));
      messenger.showSnackBar(
        SnackBar(content: Text('Unit ${unit.unitNo} held · $left')),
      );
    } on HoldException catch (e) {
      if (!mounted) return;
      setState(() => _holding = false);
      if (e.conflict) {
        ref.invalidate(projectUnitsProvider(widget.projectId));
        messenger.showSnackBar(
          const SnackBar(content: Text('Just taken by someone else — refreshing.')),
        );
      } else if (e.notAllowed) {
        messenger.showSnackBar(
          const SnackBar(content: Text("You can't hold this unit.")),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not place the hold. Try again.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _holding = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not place the hold. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <_Row>[
      if (unit.towerName != null) _Row('Tower', unit.towerName!),
      if (unit.floor != null) _Row('Floor', '${unit.floor}'),
      if (unit.configuration != null) _Row('Configuration', unit.configuration!),
      _Row('Carpet area', formatArea(unit.carpetAreaSqft)),
      _Row('List price', formatPaise(unit.listPricePaise)),
      if (unit.hasMargin) _Row('Cost (margin)', formatPaise(unit.costPaise)),
    ];

    // For a held unit, read its active hold (drives both the countdown and the
    // confirm action's hold_id).
    final holdAsync = unit.status == UnitStatus.hold
        ? ref.watch(activeHoldProvider(unit.unitId))
        : null;
    final hold = holdAsync?.asData?.value;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Unit ${unit.unitNo}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkPrimary,
                    ),
                  ),
                ),
                _StatusPill(status: unit.status),
              ],
            ),
            // Live countdown for a held unit.
            if (hold != null) ...[
              const SizedBox(height: 10),
              HoldCountdown(expiresAt: hold.expiresAt),
            ],
            const SizedBox(height: 16),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 128,
                      child: Text(
                        r.label,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.inkSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.value,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            _buildAction(hold),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(UnitHold? hold) {
    switch (unit.status) {
      case UnitStatus.available:
        return _HoldButton(available: true, busy: _holding, onHold: _startHold);
      case UnitStatus.hold:
        // Confirm-booking (manager-gated by the RPC). Enabled once we have the hold_id.
        return _ConfirmButton(
          busy: _confirming,
          onConfirm: hold == null ? null : () => _startConfirm(hold.holdId),
        );
      case UnitStatus.sold:
      case UnitStatus.blocked:
      case UnitStatus.unknown:
        return const _HoldButton(available: false, busy: false, onHold: _noop);
    }
  }

  static void _noop() {}
}

class _ConfirmButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onConfirm;

  const _ConfirmButton({required this.busy, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: busy ? null : onConfirm,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.statusSold,
          disabledBackgroundColor: AppColors.surfaceMist,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.verified_rounded, size: 18),
        label: const Text('Confirm booking',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _HoldButton extends StatelessWidget {
  final bool available;
  final bool busy;
  final VoidCallback onHold;

  const _HoldButton({
    required this.available,
    required this.busy,
    required this.onHold,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: (!available || busy) ? null : onHold,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.evergreen,
          disabledBackgroundColor: AppColors.surfaceMist,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                available ? 'Hold this unit' : 'Unavailable',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}

class _Row {
  final String label;
  final String value;
  const _Row(this.label, this.value);
}

class _StatusPill extends StatelessWidget {
  final UnitStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: status.foreground,
        ),
      ),
    );
  }
}
