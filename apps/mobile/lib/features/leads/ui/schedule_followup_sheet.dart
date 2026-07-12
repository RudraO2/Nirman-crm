// Story 3.5 — Schedule Follow-up sheet
// Date+time picker. Calls set_followup RPC. Shows existing follow-up for context.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/lead_repository.dart';
import '../providers/lead_providers.dart';

Future<bool?> showScheduleFollowupSheet(
  BuildContext context,
  String leadId,
  DateTime? currentFollowup,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ScheduleFollowupSheet(
      leadId: leadId,
      currentFollowup: currentFollowup,
    ),
  );
}

class _ScheduleFollowupSheet extends ConsumerStatefulWidget {
  final String leadId;
  final DateTime? currentFollowup;
  const _ScheduleFollowupSheet({required this.leadId, required this.currentFollowup});

  @override
  ConsumerState<_ScheduleFollowupSheet> createState() => _ScheduleFollowupSheetState();
}

class _ScheduleFollowupSheetState extends ConsumerState<_ScheduleFollowupSheet> {
  DateTime? _picked;
  bool _loading = false;

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initDate = widget.currentFollowup?.isAfter(now) == true
        ? widget.currentFollowup!
        : now.add(const Duration(days: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.accentStrong,
            surface: AppColors.surfaceRaised,
            onSurface: AppColors.inkPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initDate.hour, minute: initDate.minute),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.accentStrong,
            surface: AppColors.surfaceRaised,
            onSurface: AppColors.inkPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null) return;

    setState(() {
      _picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    final at = _picked;
    if (at == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(leadRepositoryProvider).setFollowup(widget.leadId, at);
      ref.invalidate(myLeadsProvider);
      ref.invalidate(leadByIdProvider(widget.leadId));
      if (mounted) Navigator.of(context).pop(true);
    } on OfflineQueued {
      // Saved to the offline queue — treated as success (replays when online).
      ref.invalidate(myLeadsProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Follow-up saved offline — will sync when back online.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not schedule follow-up.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 42, height: 4.5, decoration: BoxDecoration(color: AppColors.borderStrong, borderRadius: BorderRadius.circular(99)))),
          const SizedBox(height: 16),
          Text('Schedule follow-up', style: AppType.display(fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.inkPrimary)),
          const SizedBox(height: 3),
          Text('Alarm rings on your phone at this time', style: TextStyle(fontSize: 13, color: AppColors.inkSecondary)),

          if (widget.currentFollowup != null) ...[
            const SizedBox(height: 4),
            Text(
              'Current: ${_fmt(widget.currentFollowup!)}',
              style: TextStyle(fontSize: 13, color: AppColors.inkSecondary),
            ),
          ],

          const SizedBox(height: 20),

          // Quick options
          _QuickOption(
            label: 'Tomorrow 9am',
            onTap: () {
              final t = DateTime.now();
              setState(() => _picked = DateTime(t.year, t.month, t.day + 1, 9, 0));
            },
          ),
          const SizedBox(height: 8),
          _QuickOption(
            label: 'In 3 days, 10am',
            onTap: () {
              final t = DateTime.now();
              setState(() => _picked = DateTime(t.year, t.month, t.day + 3, 10, 0));
            },
          ),
          const SizedBox(height: 8),
          _QuickOption(
            label: 'Next week',
            onTap: () {
              final t = DateTime.now();
              setState(() => _picked = DateTime(t.year, t.month, t.day + 7, 9, 0));
            },
          ),
          const SizedBox(height: 8),

          // Custom picker
          GestureDetector(
            onTap: _pickDateTime,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _picked != null ? AppColors.brass : AppColors.borderStrong, width: 1.5),
              ),
              child: Row(children: [
                Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.inkSecondary),
                const SizedBox(width: 10),
                Text(
                  _picked != null ? _fmt(_picked!) : 'Custom date & time',
                  style: TextStyle(
                    fontSize: 14,
                    color: _picked != null ? AppColors.inkPrimary : AppColors.inkSecondary,
                    fontWeight: _picked != null ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _picked == null || _loading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brass,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.brass.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    return '${l.day}/${l.month}/${l.year} $h:$m ${l.hour >= 12 ? 'pm' : 'am'}';
  }
}

class _QuickOption extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickOption({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderStrong, width: 1.5),
        ),
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkPrimary)),
      ),
    );
  }
}
