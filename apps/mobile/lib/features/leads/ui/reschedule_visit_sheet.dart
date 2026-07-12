// Story 2.6 — Reschedule Visit bottom sheet
// Three shortcuts: +2h (from current visit_date or now), Tomorrow 9am, Custom picker.
// Returns true on success so caller can invalidate providers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/lead_repository.dart';

Future<bool?> showRescheduleVisitSheet(
  BuildContext context,
  String leadId,
  DateTime? currentVisitDate,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RescheduleVisitSheet(
      leadId: leadId,
      currentVisitDate: currentVisitDate,
    ),
  );
}

class _RescheduleVisitSheet extends ConsumerStatefulWidget {
  final String leadId;
  final DateTime? currentVisitDate;

  const _RescheduleVisitSheet({
    required this.leadId,
    required this.currentVisitDate,
  });

  @override
  ConsumerState<_RescheduleVisitSheet> createState() => _RescheduleVisitSheetState();
}

class _RescheduleVisitSheetState extends ConsumerState<_RescheduleVisitSheet> {
  bool _loading = false;
  String? _error;

  DateTime get _base => widget.currentVisitDate ?? DateTime.now();

  Future<void> _save(DateTime newDate) async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(leadRepositoryProvider).rescheduleVisit(widget.leadId, newDate);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      // Calm mapping (audit medium): never surface a raw exception dump here.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't reschedule the visit. Check your connection and try again.";
        });
      }
    }
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _base.isAfter(now) ? _base : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.accentStrong,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _base.hour, minute: _base.minute),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.accentStrong,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (pickedTime == null || !mounted) return;

    final combined = DateTime(
      pickedDate.year, pickedDate.month, pickedDate.day,
      pickedTime.hour, pickedTime.minute,
    );
    await _save(combined);
  }

  @override
  Widget build(BuildContext context) {
    final base       = _base;
    final plusTwoH   = base.add(const Duration(hours: 2));
    final tomorrowNow = DateTime.now().add(const Duration(days: 1));
    final tomorrow9am = DateTime(tomorrowNow.year, tomorrowNow.month, tomorrowNow.day, 9);

    String _fmt(DateTime dt) {
      final l = dt.toLocal();
      final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
      final m = l.minute.toString().padLeft(2, '0');
      final ampm = l.hour >= 12 ? 'pm' : 'am';
      return '${l.day}/${l.month} $h:$m $ampm';
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 12, 24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 42, height: 4.5,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Reschedule Visit',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.inkPrimary,
            ),
          ),
          const SizedBox(height: 6),
          if (widget.currentVisitDate != null)
            Text(
              'Current: ${_fmt(widget.currentVisitDate!.toLocal())}',
              style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary),
            ),
          const SizedBox(height: 20),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 13, color: AppColors.error),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // +2h option
          _OptionTile(
            icon: Icons.schedule_rounded,
            label: '+2 hours',
            subtitle: _fmt(plusTwoH),
            loading: _loading,
            onTap: () => _save(plusTwoH),
          ),
          const SizedBox(height: 8),

          // Tomorrow 9am
          _OptionTile(
            icon: Icons.wb_sunny_outlined,
            label: 'Tomorrow, 9 am',
            subtitle: _fmt(tomorrow9am),
            loading: _loading,
            onTap: () => _save(tomorrow9am),
          ),
          const SizedBox(height: 8),

          // Custom
          _OptionTile(
            icon: Icons.calendar_month_outlined,
            label: 'Pick date & time',
            subtitle: 'Choose any date',
            loading: _loading,
            onTap: _pickCustom,
          ),

          const SizedBox(height: 8),
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(false),
            child: const Center(
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.inkSecondary, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool loading;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderHairline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.accentStrong),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.inkPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.inkSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.inkDisabled),
          ],
        ),
      ),
    );
  }
}
