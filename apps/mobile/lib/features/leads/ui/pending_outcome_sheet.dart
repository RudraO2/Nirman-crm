// Story 3.2 — Pending Outcome prompt
// Non-blocking bottom sheet: shown when app returns to foreground with a pending call.
// Provides: status selector, optional remarks, optional follow-up scheduler,
// and "Didn't actually call" escape hatch.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../data/lead_repository.dart';
import '../data/models/lead_model.dart';
import '../providers/lead_providers.dart';
import '../../motivation/data/motivation_repository.dart';
import '../../motivation/providers/motivation_providers.dart';
import '../../motivation/ui/sold_celebration_overlay.dart';

Future<void> showPendingOutcomeSheet(
  BuildContext context,
  LeadListItem lead,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PendingOutcomeSheet(lead: lead),
  );
}

class _PendingOutcomeSheet extends ConsumerStatefulWidget {
  final LeadListItem lead;
  const _PendingOutcomeSheet({required this.lead});

  @override
  ConsumerState<_PendingOutcomeSheet> createState() => _PendingOutcomeSheetState();
}

class _PendingOutcomeSheetState extends ConsumerState<_PendingOutcomeSheet> {
  String _selectedStatus = '';
  final _remarksCtrl = TextEditingController();
  bool _scheduleFollowup = false;
  DateTime? _followupAt;
  bool _loading = false;

  static const _statuses = ['warm', 'cold', 'hot', 'dead', 'sold', 'future'];

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.lead.status;
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Re-entry guard — set _loading FIRST so a double-tap can't fire twice.
    if (_loading) return;
    setState(() => _loading = true);
    final wasSold = _selectedStatus == 'sold' && widget.lead.status != 'sold';
    try {
      await ref.read(leadRepositoryProvider).submitCallOutcome(
        leadId:     widget.lead.id,
        newStatus:  _selectedStatus,
        remarks:    _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
        followupAt: _scheduleFollowup ? _followupAt : null,
      );
      ref.invalidate(myLeadsProvider);
      ref.invalidate(myMotivationStatsProvider);
      ref.invalidate(myMonthlyBestProvider);
      if (!mounted) return;
      if (wasSold) {
        // Fire admin push (best-effort) and play the celebration (Story 7.2).
        ref.read(motivationRepositoryProvider).notifyAdminSold(widget.lead.id, widget.lead.name);
        await showSoldCelebration(context, ref, leadId: widget.lead.id, leadName: widget.lead.name);
      }
      if (mounted) Navigator.of(context).pop();
    } on OfflineQueued {
      // Saved to the offline queue — treated as success (replays when online).
      ref.invalidate(myLeadsProvider);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Outcome saved offline — will sync when back online.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save outcome. Try again.')),
        );
      }
    }
  }

  Future<void> _didntCall() async {
    setState(() => _loading = true);
    try {
      await ref.read(leadRepositoryProvider).clearPendingOutcome(widget.lead.id);
      ref.invalidate(myLeadsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not clear outcome. Try again.')),
        );
      }
    }
  }

  Future<void> _pickFollowupDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
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
      initialTime: const TimeOfDay(hour: 10, minute: 0),
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
      _followupAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
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
          // Handle
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

          // Header
          Text(
            'How did the call go?',
            style: GoogleFonts.fraunces(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: AppColors.inkPrimary,
            ),
          ),
          if (widget.lead.name != null) ...[
            const SizedBox(height: 2),
            Text(
              widget.lead.name!,
              style: TextStyle(fontSize: 14, color: AppColors.inkSecondary),
            ),
          ],
          const SizedBox(height: 20),

          // Status selector
          Text(
            'Status',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _statuses.map((s) {
              final selected = s == _selectedStatus;
              final color = s.statusColor;
              return GestureDetector(
                onTap: () => setState(() => _selectedStatus = s),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected ? s.statusBgColor : AppColors.paper,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: selected ? color : AppColors.borderStrong,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.statusLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: selected ? color : AppColors.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Remarks
          TextField(
            controller: _remarksCtrl,
            maxLines: 2,
            minLines: 1,
            style: TextStyle(fontSize: 14, color: AppColors.inkPrimary),
            decoration: InputDecoration(
              hintText: 'Add a remark (optional)',
              hintStyle: TextStyle(color: AppColors.inkDisabled, fontSize: 14),
              filled: true,
              fillColor: AppColors.paper,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderStrong, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderStrong, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.brass, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Schedule follow-up toggle
          Row(
            children: [
              SizedBox(
                width: 36,
                height: 20,
                child: Switch.adaptive(
                  value: _scheduleFollowup,
                  onChanged: (v) {
                    setState(() => _scheduleFollowup = v);
                    if (v && _followupAt == null) _pickFollowupDate();
                  },
                  activeColor: AppColors.accentStrong,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 10),
              Text('Schedule Follow-up', style: TextStyle(fontSize: 14, color: AppColors.inkPrimary)),
              if (_scheduleFollowup && _followupAt != null) ...[
                const Spacer(),
                GestureDetector(
                  onTap: _pickFollowupDate,
                  child: Text(
                    _formatDate(_followupAt!),
                    style: TextStyle(fontSize: 13, color: AppColors.accentStrong, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ],
          ),
          if (_scheduleFollowup && _followupAt == null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickFollowupDate,
              child: Text(
                'Tap to pick date & time',
                style: TextStyle(fontSize: 13, color: AppColors.accentStrong),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brass,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.brass.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save outcome', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: 8),

          // Escape hatch
          Center(
            child: TextButton(
              onPressed: _loading ? null : _didntCall,
              child: Text(
                "Didn't actually call",
                style: TextStyle(fontSize: 13, color: AppColors.inkSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    final ampm = l.hour >= 12 ? 'pm' : 'am';
    return '${l.day}/${l.month} $h:$m $ampm';
  }
}
