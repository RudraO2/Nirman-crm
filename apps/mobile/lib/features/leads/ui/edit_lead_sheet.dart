// Story 2.4 — Edit Lead bottom sheet
// Pre-filled with all existing lead data (fetched via get_lead_by_id).
// Calls update-lead Edge Function on save.
// Status picker visible inline (no step-1 gate — status already chosen).
// is_incomplete auto-recomputed server-side; badge updates on next list refresh.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/lead_repository.dart';
import '../data/models/lead_model.dart';
import '../providers/lead_providers.dart';
import '../../motivation/data/motivation_repository.dart';
import '../../motivation/providers/motivation_providers.dart';
import '../../motivation/ui/sold_celebration_overlay.dart';

Future<bool?> showEditLeadSheet(BuildContext context, LeadDetail lead) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceBase,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => EditLeadSheet(lead: lead),
  );
}

// ---------------------------------------------------------------------------
class EditLeadSheet extends ConsumerStatefulWidget {
  final LeadDetail lead;
  const EditLeadSheet({super.key, required this.lead});

  @override
  ConsumerState<EditLeadSheet> createState() => _EditLeadSheetState();
}

class _EditLeadSheetState extends ConsumerState<EditLeadSheet> {
  late String _status;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _budgetMinCtrl;
  late final TextEditingController _budgetMaxCtrl;
  late final TextEditingController _remarksCtrl;
  String? _source;
  String? _propertyType;
  String? _ticketSize;
  String? _interestType;
  late final Set<String> _projectIds;

  bool _saving   = false;
  String? _errorMsg;
  String? _duplicateOwner;

  @override
  void initState() {
    super.initState();
    final l = widget.lead;
    _status       = l.status;
    _source       = l.source;
    _propertyType = l.propertyType;
    _ticketSize   = l.ticketSize;
    _interestType = l.interestType;
    _projectIds   = Set<String>.from(l.projectIds);

    _phoneCtrl     = TextEditingController(text: l.displayPhone);
    _nameCtrl      = TextEditingController(text: l.name ?? '');
    _locationCtrl  = TextEditingController(text: l.location ?? '');
    // Display in rupees (DB stores paise: ₹1 = 100 paise)
    _budgetMinCtrl = TextEditingController(
      text: l.budgetMin != null ? '${l.budgetMin! ~/ 100}' : '',
    );
    _budgetMaxCtrl = TextEditingController(
      text: l.budgetMax != null ? '${l.budgetMax! ~/ 100}' : '',
    );
    _remarksCtrl = TextEditingController(text: l.remarks ?? '');
  }

  @override
  void dispose() {
    _phoneCtrl.dispose(); _nameCtrl.dispose(); _locationCtrl.dispose();
    _budgetMinCtrl.dispose(); _budgetMaxCtrl.dispose(); _remarksCtrl.dispose();
    super.dispose();
  }

  bool get _canSave => _phoneCtrl.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() { _saving = true; _errorMsg = null; _duplicateOwner = null; });

    final payload = UpdateLeadPayload(
      leadId:        widget.lead.id,
      status:        _status,
      phone:         _phoneCtrl.text.trim(),
      source:        _source,
      name:          _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      propertyType:  _propertyType,
      location:      _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
      // Convert rupees → paise on save
      budgetMin:     () { final r = int.tryParse(_budgetMinCtrl.text.replaceAll(',', '')); return r == null ? null : r * 100; }(),
      budgetMax:     () { final r = int.tryParse(_budgetMaxCtrl.text.replaceAll(',', '')); return r == null ? null : r * 100; }(),
      ticketSize:    _ticketSize,
      remarks:       _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
      interestType:  _interestType,
      projectIds:    _projectIds.toList(),
    );

    final wasSold = _status == 'sold' && widget.lead.status != 'sold';
    try {
      await ref.read(leadRepositoryProvider).updateLead(payload);
      // Refresh both the list and this lead's detail
      ref.invalidate(myLeadsProvider);
      ref.invalidate(leadByIdProvider(widget.lead.id));
      ref.invalidate(myMotivationStatsProvider);
      ref.invalidate(myMonthlyBestProvider);
      if (!mounted) return;
      if (wasSold) {
        ref.read(motivationRepositoryProvider).notifyAdminSold(widget.lead.id, widget.lead.name);
        await showSoldCelebration(context, ref, leadId: widget.lead.id, leadName: widget.lead.name);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on LeadReassignedError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This lead was just reassigned. Refreshing.')),
      );
      Navigator.of(context).pop();
      ref.invalidate(leadByIdProvider(widget.lead.id));
      ref.invalidate(myLeadsProvider);
    } on DuplicateLeadError catch (e) {
      setState(() { _errorMsg = e.message; _duplicateOwner = e.ownerName; _saving = false; });
    } on LeadSubmitException catch (e) {
      // Server-written validation text — safe to show verbatim.
      setState(() { _errorMsg = e.message; _saving = false; });
    } catch (_) {
      setState(() {
        _errorMsg = "Couldn't save the changes. Check your connection and try again.";
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (_, scrollCtrl) {
        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              color: AppColors.surfaceBase,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42, height: 4.5,
                      decoration: BoxDecoration(
                        color: AppColors.borderStrong,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Edit lead',
                          style: AppType.display(
                            fontSize: 21,
                            fontWeight: FontWeight.w500,
                            color: AppColors.inkPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.inkSecondary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            // Scrollable form
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                children: [
                  // ── Status ─────────────────────────────────────────────
                  _FieldLabel(label: 'Status', required: true),
                  const SizedBox(height: 6),
                  _StatusChipGroup(
                    selected: _status,
                    onSelected: (s) => setState(() => _status = s),
                  ),
                  const SizedBox(height: 20),

                  // ── Phone ──────────────────────────────────────────────
                  _FieldLabel(label: 'Phone', required: true),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-+()]'))],
                    onChanged: (_) => setState(() {}),
                    decoration: _inputDecoration(
                      hint: '98765 43210',
                      errorText: _errorMsg != null && _duplicateOwner == null ? _errorMsg : null,
                    ),
                    style: TextStyle(color: AppColors.inkPrimary, fontSize: 16),
                  ),
                  if (_duplicateOwner != null) ...[
                    const SizedBox(height: 8),
                    _DuplicateError(owner: _duplicateOwner!),
                  ],
                  const SizedBox(height: 20),

                  // ── Name ───────────────────────────────────────────────
                  _FieldLabel(label: 'Name'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDecoration(hint: 'Customer name'),
                    style: TextStyle(color: AppColors.inkPrimary, fontSize: 16),
                  ),
                  const SizedBox(height: 20),

                  // ── Source ─────────────────────────────────────────────
                  _FieldLabel(label: 'Source'),
                  const SizedBox(height: 6),
                  _ChipGroup<String>(
                    options: const {'walk_in': 'Walk-in', 'referral': 'Referral', 'associate': 'Associate', 'ad': 'Ad'},
                    selected: _source,
                    onSelected: (v) => setState(() => _source = v == _source ? null : v),
                  ),
                  const SizedBox(height: 20),

                  // ── Projects ────────────────────────────────────────────
                  _FieldLabel(label: 'Project'),
                  const SizedBox(height: 6),
                  _ProjectPicker(
                    selectedIds: _projectIds,
                    onChanged: (id, sel) => setState(() { sel ? _projectIds.add(id) : _projectIds.remove(id); }),
                  ),
                  const SizedBox(height: 20),

                  // ── Property Type ──────────────────────────────────────
                  _FieldLabel(label: 'Property Type'),
                  const SizedBox(height: 6),
                  _ChipGroup<String>(
                    options: const {'Flat': 'Flat', 'Plot': 'Plot', 'Villa': 'Villa', 'Commercial': 'Commercial'},
                    selected: _propertyType,
                    onSelected: (v) => setState(() => _propertyType = v == _propertyType ? null : v),
                  ),
                  const SizedBox(height: 20),

                  // ── Ticket Size ────────────────────────────────────────
                  _FieldLabel(label: 'Ticket Size'),
                  const SizedBox(height: 6),
                  _ChipGroup<String>(
                    options: const {'2BHK': '2BHK', '3BHK': '3BHK', '4BHK': '4BHK', 'Penthouse': 'Penthouse'},
                    selected: _ticketSize,
                    onSelected: (v) => setState(() => _ticketSize = v == _ticketSize ? null : v),
                  ),
                  const SizedBox(height: 20),

                  // ── Interest Type (Future only) ────────────────────────
                  if (_status == 'future') ...[
                    _FieldLabel(label: 'Interest Type', required: true),
                    const SizedBox(height: 6),
                    _ChipGroup<String>(
                      options: const {
                        'Flat': 'Flat', 'Plot': 'Plot', 'Villa': 'Villa',
                        'Commercial': 'Commercial', 'Studio': 'Studio', 'Penthouse': 'Penthouse',
                      },
                      selected: _interestType,
                      onSelected: (v) => setState(() => _interestType = v == _interestType ? null : v),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Location ───────────────────────────────────────────
                  _FieldLabel(label: 'Location'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _locationCtrl,
                    decoration: _inputDecoration(hint: 'Area or city'),
                    style: TextStyle(color: AppColors.inkPrimary, fontSize: 16),
                  ),
                  const SizedBox(height: 20),

                  // ── Budget ─────────────────────────────────────────────
                  _FieldLabel(label: 'Budget (₹)'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _budgetMinCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: _inputDecoration(hint: 'Min'),
                          style: TextStyle(color: AppColors.inkPrimary, fontSize: 16),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('–', style: TextStyle(color: AppColors.inkSecondary, fontSize: 20)),
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: _budgetMaxCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: _inputDecoration(hint: 'Max'),
                          style: TextStyle(color: AppColors.inkPrimary, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Remarks ────────────────────────────────────────────
                  _FieldLabel(label: 'Remarks'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _remarksCtrl,
                    maxLines: 3,
                    decoration: _inputDecoration(hint: 'Notes about this lead…'),
                    style: TextStyle(color: AppColors.inkPrimary, fontSize: 16),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),

            // Sticky save bar
            _SaveBar(canSave: _canSave, saving: _saving, onSave: _save),
          ],
        );
      },
    );
  }
}

// ── Reused widgets ────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool required;
  const _FieldLabel({required this.label, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkSecondary,
        ),
      ),
      if (required) ...[
        const SizedBox(width: 3),
        Text('*', style: TextStyle(color: AppColors.statusHot, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    ]);
  }
}

InputDecoration _inputDecoration({String? hint, String? errorText}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.inkDisabled, fontSize: 15),
    errorText: errorText,
    errorStyle: TextStyle(color: AppColors.error, fontSize: 12),
    filled: true,
    fillColor: AppColors.paper,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.borderStrong, width: 1.5)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.borderStrong, width: 1.5)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.brass, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.error, width: 1.5)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.error, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

class _StatusChipGroup extends StatelessWidget {
  final String selected;
  final void Function(String) onSelected;
  const _StatusChipGroup({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: ['hot', 'warm', 'cold', 'future', 'sold', 'dead'].map((s) {
        final active = s == selected;
        final color  = s.statusColor;
        return GestureDetector(
          onTap: () => onSelected(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: active ? s.statusBgColor : AppColors.paper,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: active ? color : AppColors.borderStrong, width: 1.5),
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
                    color: active ? color : AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ChipGroup<T> extends StatelessWidget {
  final Map<T, String> options;
  final T? selected;
  final void Function(T) onSelected;
  const _ChipGroup({required this.options, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: options.entries.map((e) {
        final active = e.key == selected;
        return GestureDetector(
          onTap: () => onSelected(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: active ? AppColors.evergreen : AppColors.paper,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: active ? AppColors.evergreen : AppColors.borderStrong, width: 1.5),
            ),
            child: Text(e.value, style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.brassBright : AppColors.inkSecondary,
            )),
          ),
        );
      }).toList(),
    );
  }
}

class _ProjectPicker extends ConsumerWidget {
  final Set<String> selectedIds;
  final void Function(String, bool) onChanged;
  const _ProjectPicker({required this.selectedIds, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(availableProjectsProvider).when(
      loading: () => const SizedBox(height: 36, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
      error: (_, __) => Text('Could not load projects', style: TextStyle(color: AppColors.error, fontSize: 13)),
      data: (projects) {
        if (projects.isEmpty) return Text('No projects configured', style: TextStyle(color: AppColors.inkDisabled, fontSize: 14));
        return Wrap(
          spacing: 8, runSpacing: 8,
          children: projects.map((p) {
            final active = selectedIds.contains(p.id);
            return GestureDetector(
              onTap: () => onChanged(p.id, !active),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.evergreen : AppColors.paper,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: active ? AppColors.evergreen : AppColors.borderStrong, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (active) ...[Icon(Icons.check_rounded, size: 14, color: AppColors.brassBright), const SizedBox(width: 4)],
                    Text(p.name, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: active ? AppColors.brassBright : AppColors.inkSecondary)),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _DuplicateError extends StatelessWidget {
  final String owner;
  const _DuplicateError({required this.owner});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorFill.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('This phone is linked to a lead under $owner.', style: TextStyle(color: AppColors.error, fontSize: 13, height: 1.4))),
        ],
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  final bool canSave;
  final bool saving;
  final Future<void> Function() onSave;
  const _SaveBar({required this.canSave, required this.saving, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      color: AppColors.surfaceBase,
      padding: EdgeInsets.fromLTRB(24, 12, 24, 16 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(color: AppColors.borderHairline, height: 1),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: canSave && !saving ? onSave : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brass,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.surfaceMist,
                disabledForegroundColor: AppColors.inkDisabled,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
              child: saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
                  : const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
