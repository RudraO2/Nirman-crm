// Story 16.2-mobile — log an amendment against a held/sold unit for its lead.
//
// Reached from the booking-dashboard hold card (which carries unit_id + lead_id +
// unit_no). log_amendment is authoritative; this sheet only collects a description
// and maps guard rejections to calm inline messages. On success the amendment is
// dual-logged to the lead Timeline server-side (shows as "Amendment logged").

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/amendments_repository.dart';

/// Returns true if an amendment was logged.
Future<bool?> showLogAmendmentSheet(
  BuildContext context, {
  required String unitId,
  required String leadId,
  required String unitNo,
  required String leadLabel,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceBase,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => LogAmendmentSheet(
      unitId: unitId,
      leadId: leadId,
      unitNo: unitNo,
      leadLabel: leadLabel,
    ),
  );
}

class LogAmendmentSheet extends ConsumerStatefulWidget {
  final String unitId;
  final String leadId;
  final String unitNo;
  final String leadLabel;

  const LogAmendmentSheet({
    super.key,
    required this.unitId,
    required this.leadId,
    required this.unitNo,
    required this.leadLabel,
  });

  @override
  ConsumerState<LogAmendmentSheet> createState() => _LogAmendmentSheetState();
}

class _LogAmendmentSheetState extends ConsumerState<LogAmendmentSheet> {
  final _descCtrl = TextEditingController();
  bool _saving = false;
  String? _errorMsg;

  bool get _canSave => !_saving && _descCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _errorMsg = null;
    });
    try {
      await ref.read(amendmentsRepositoryProvider).logAmendment(
            unitId: widget.unitId,
            leadId: widget.leadId,
            description: _descCtrl.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on LogAmendmentException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.friendly;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMsg = "Couldn't log the amendment. Try again.";
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 16, 22, 16 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 42,
            height: 4.5,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.borderStrong,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Text(
            'Log amendment',
            style: AppType.display(
              fontSize: 21,
              fontWeight: FontWeight.w500,
              color: AppColors.inkPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Unit ${widget.unitNo} · ${widget.leadLabel}',
            style: TextStyle(fontSize: 13, color: AppColors.inkSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            autofocus: true,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: AppColors.inkPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'What change did the client request?',
              hintStyle: TextStyle(color: AppColors.inkDisabled, fontSize: 15),
              errorText: _errorMsg,
              filled: true,
              fillColor: AppColors.paper,
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
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _canSave ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brass,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.surfaceMist,
                disabledForegroundColor: AppColors.inkDisabled,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text('Log amendment',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
