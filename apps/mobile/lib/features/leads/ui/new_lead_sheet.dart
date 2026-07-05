// Story 2.3 — Status-first New Lead bottom sheet
// UX spec: EXPERIENCE.md §Component Patterns → "Status-first new-lead sheet"
//   Step 1: Full-screen Status grid (6 options, large touch targets, no other fields)
//   Step 2: Phone field auto-focused + optional fields + "Save Incomplete" CTA
// Accessibility: WCAG 2.1 AA, ≥48dp tap targets, color NOT only signal

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../data/lead_repository.dart';
import '../data/models/lead_model.dart';
import '../providers/lead_providers.dart';

// ---------------------------------------------------------------------------
// Entry point — call this from FAB
// ---------------------------------------------------------------------------
Future<bool?> showNewLeadSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceBase,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => const NewLeadSheet(),
  );
}

// ---------------------------------------------------------------------------
// Root sheet widget
// ---------------------------------------------------------------------------
class NewLeadSheet extends ConsumerStatefulWidget {
  const NewLeadSheet({super.key});

  @override
  ConsumerState<NewLeadSheet> createState() => _NewLeadSheetState();
}

class _NewLeadSheetState extends ConsumerState<NewLeadSheet> {
  // Step
  String? _status; // null = step 1 (status picker)

  // Form controllers
  final _phoneCtrl    = TextEditingController();
  final _secondaryPhoneCtrl = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _budgetMinCtrl = TextEditingController();
  final _budgetMaxCtrl = TextEditingController();
  final _remarksCtrl  = TextEditingController();

  // Dropdown / chip selections
  String? _source;
  String? _propertyType;
  String? _ticketSize;
  final Set<String> _projectIds = {};

  // UI state
  bool _saving = false;
  String? _errorMsg;
  String? _duplicateOwner;
  String? _duplicateLeadId;

  bool get _canSave =>
      _status != null && _phoneCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _secondaryPhoneCtrl.dispose();
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _budgetMinCtrl.dispose();
    _budgetMaxCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Save
  // ------------------------------------------------------------------
  Future<void> _save({bool overrideDuplicate = false}) async {
    if (!_canSave || _saving) return;
    setState(() {
      _saving = true;
      _errorMsg = null;
      _duplicateOwner = null;
      _duplicateLeadId = null;
    });

    // Form input is in rupees; DB stores paise (₹1 = 100 paise)
    final budgetMinRupees = int.tryParse(_budgetMinCtrl.text.replaceAll(',', ''));
    final budgetMaxRupees = int.tryParse(_budgetMaxCtrl.text.replaceAll(',', ''));
    final budgetMin = budgetMinRupees == null ? null : budgetMinRupees * 100;
    final budgetMax = budgetMaxRupees == null ? null : budgetMaxRupees * 100;

    final payload = CreateLeadPayload(
      status:           _status!,
      phone:            _phoneCtrl.text.trim(),
      secondaryPhone:   _secondaryPhoneCtrl.text.trim().isEmpty ? null : _secondaryPhoneCtrl.text.trim(),
      source:           _source,
      name:             _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      propertyType:     _propertyType,
      location:         _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
      budgetMin:        budgetMin,
      budgetMax:        budgetMax,
      ticketSize:       _ticketSize,
      remarks:          _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
      projectIds:       _projectIds.toList(),
      overrideDuplicate: overrideDuplicate,
    );

    try {
      final result = await ref.read(leadRepositoryProvider).createLead(payload);
      if (!mounted) return;
      // Story 13.3 — surface the system visit code + free WhatsApp delivery.
      if (result.customerCode != null) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _CustomerCodeDialog(
            code: result.customerCode!,
            whatsappLink: result.whatsappLink,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on DuplicateLeadError catch (e) {
      setState(() {
        _errorMsg = e.message;
        _duplicateOwner = e.ownerName;
        _duplicateLeadId = e.existingLeadId;
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  // ------------------------------------------------------------------
  // Build — ONE sheet: status chips at the top + full form below (§6.5)
  // ------------------------------------------------------------------
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
            // Grab handle
            Container(
              width: 42, height: 4.5,
              margin: const EdgeInsets.fromLTRB(0, 10, 0, 6),
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            // Scrollable form body
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                children: [
                  Text(
                    'New lead',
                    style: GoogleFonts.fraunces(
                      fontSize: 21,
                      fontWeight: FontWeight.w500,
                      color: AppColors.inkPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Status first, details below — one screen',
                    style: TextStyle(fontSize: 13, color: AppColors.inkSecondary),
                  ),

                  // ── Status (required) ──
                  const SizedBox(height: 16),
                  _FieldLabel(label: 'Status', required: true),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const ['hot', 'warm', 'cold', 'future', 'sold', 'dead']
                        .map((s) => _StatusChip(
                              status: s,
                              selected: _status == s,
                              onTap: () => setState(() => _status = s),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 4),

                  // ── Phone (required) ──
                  _FieldLabel(label: 'Phone', required: true),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _phoneCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-+()]'))],
                    onChanged: (_) => setState(() {}),
                    decoration: _inputDecoration(
                      hint: '98765 43210',
                      errorText: _errorMsg != null && _duplicateOwner == null ? _errorMsg : null,
                    ),
                    style: TextStyle(color: AppColors.inkPrimary, fontSize: 16),
                  ),

                  // Duplicate error + admin override
                  if (_duplicateOwner != null) ...[
                    const SizedBox(height: 8),
                    _DuplicateError(
                      owner: _duplicateOwner!,
                      onOverride: () => _save(overrideDuplicate: true),
                      saving: _saving,
                    ),
                  ],

                  const SizedBox(height: 20),

                  // ── Secondary phone (alternative / spouse) ──
                  _FieldLabel(label: 'Secondary phone'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _secondaryPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-+()]'))],
                    decoration: _inputDecoration(hint: 'Alternative / spouse number'),
                    style: TextStyle(color: AppColors.inkPrimary, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Keeps you connected if the primary number is unreachable. '
                    'Needed to mark the lead complete.',
                    style: TextStyle(fontSize: 12, color: AppColors.inkSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 20),

                  // ── Name ──
                  _FieldLabel(label: 'Name'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDecoration(hint: 'Customer name'),
                    style: TextStyle(color: AppColors.inkPrimary, fontSize: 16),
                  ),
                  const SizedBox(height: 20),

                  // ── Source ──
                  _FieldLabel(label: 'Source'),
                  const SizedBox(height: 6),
                  _ChipGroup<String>(
                    options: const {
                      'walk_in': 'Walk-in',
                      'referral': 'Referral',
                      'cold_call': 'Cold Calling',
                      'employee_referral': 'Employee Ref',
                      'associate': 'Associate',
                      'ad': 'Ad',
                    },
                    selected: _source,
                    onSelected: (v) => setState(() => _source = v == _source ? null : v),
                  ),
                  const SizedBox(height: 20),

                  // ── Projects ──
                  _FieldLabel(label: 'Project'),
                  const SizedBox(height: 6),
                  _ProjectPicker(
                    selectedIds: _projectIds,
                    onChanged: (id, selected) => setState(() {
                      selected ? _projectIds.add(id) : _projectIds.remove(id);
                    }),
                  ),
                  const SizedBox(height: 20),

                  // ── Property Type ──
                  _FieldLabel(label: 'Property Type'),
                  const SizedBox(height: 6),
                  _ChipGroup<String>(
                    options: const {
                      'Flat': 'Flat',
                      'Plot': 'Plot',
                      'Villa': 'Villa',
                      'Commercial': 'Commercial',
                    },
                    selected: _propertyType,
                    onSelected: (v) => setState(() =>
                      _propertyType = v == _propertyType ? null : v),
                  ),
                  const SizedBox(height: 20),

                  // ── Ticket Size ──
                  _FieldLabel(label: 'Ticket Size'),
                  const SizedBox(height: 6),
                  _ChipGroup<String>(
                    options: const {
                      '2BHK': '2BHK',
                      '3BHK': '3BHK',
                      '4BHK': '4BHK',
                      'Penthouse': 'Penthouse',
                    },
                    selected: _ticketSize,
                    onSelected: (v) => setState(() =>
                      _ticketSize = v == _ticketSize ? null : v),
                  ),
                  const SizedBox(height: 20),

                  // ── Location ──
                  _FieldLabel(label: 'Location'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _locationCtrl,
                    decoration: _inputDecoration(hint: 'Area or city'),
                    style: TextStyle(color: AppColors.inkPrimary, fontSize: 16),
                  ),
                  const SizedBox(height: 20),

                  // ── Budget ──
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

                  // ── Remarks ──
                  _FieldLabel(label: 'Remarks'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _remarksCtrl,
                    maxLines: 3,
                    decoration: _inputDecoration(hint: 'Notes about this lead…'),
                    style: TextStyle(color: AppColors.inkPrimary, fontSize: 16),
                  ),

                  // Bottom padding for the sticky button bar
                  const SizedBox(height: 100),
                ],
              ),
            ),

            // ── Sticky save button ──
            _SaveBar(
              canSave: _canSave,
              saving: _saving,
              onSave: _save,
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Status chip (single-select, required) — dot + capitalized word
// ---------------------------------------------------------------------------
class _StatusChip extends StatelessWidget {
  final String status;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({required this.status, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = status.statusColor;
    final label = status.statusLabel;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label status',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? status.statusBgColor : AppColors.paper,
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
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? color : AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form helpers
// ---------------------------------------------------------------------------
class _FieldLabel extends StatelessWidget {
  final String label;
  final bool required;

  const _FieldLabel({required this.label, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.inkSecondary,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 3),
          Text('*', style: TextStyle(color: AppColors.statusHot, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ],
    );
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
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.error, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.error, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

// ---------------------------------------------------------------------------
// Chip group (single-select, tap to deselect)
// ---------------------------------------------------------------------------
class _ChipGroup<T> extends StatelessWidget {
  final Map<T, String> options;
  final T? selected;
  final void Function(T value) onSelected;

  const _ChipGroup({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((e) {
        final isActive = e.key == selected;
        return GestureDetector(
          onTap: () => onSelected(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: isActive ? AppColors.evergreen : AppColors.paper,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: isActive ? AppColors.evergreen : AppColors.borderStrong,
                width: 1.5,
              ),
            ),
            child: Text(
              e.value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isActive ? AppColors.brassBright : AppColors.inkSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Project picker — loads from Riverpod, multi-select chips
// ---------------------------------------------------------------------------
class _ProjectPicker extends ConsumerWidget {
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onChanged;

  const _ProjectPicker({required this.selectedIds, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(availableProjectsProvider);

    return projectsAsync.when(
      loading: () => const SizedBox(
        height: 36,
        child: Center(child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
      ),
      error: (_, __) => Text(
        'Could not load projects',
        style: TextStyle(color: AppColors.error, fontSize: 13),
      ),
      data: (projects) {
        if (projects.isEmpty) {
          return Text(
            'No projects configured',
            style: TextStyle(color: AppColors.inkDisabled, fontSize: 14),
          );
        }
        return Wrap(
          spacing: 8, runSpacing: 8,
          children: projects.map((p) {
            final active = selectedIds.contains(p.id);
            return GestureDetector(
              onTap: () => onChanged(p.id, !active),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? AppColors.evergreen : AppColors.paper,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: active ? AppColors.evergreen : AppColors.borderStrong,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (active) ...[
                      Icon(Icons.check_rounded, size: 14, color: AppColors.brassBright),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: active ? AppColors.brassBright : AppColors.inkSecondary,
                      ),
                    ),
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

// ---------------------------------------------------------------------------
// Duplicate error row with admin override button
// ---------------------------------------------------------------------------
class _DuplicateError extends StatelessWidget {
  final String owner;
  final VoidCallback onOverride;
  final bool saving;

  const _DuplicateError({
    required this.owner,
    required this.onOverride,
    required this.saving,
  });

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This lead already exists under $owner.',
                  style: TextStyle(color: AppColors.error, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 6),
                // Override button — only visible to admins (server enforces role)
                GestureDetector(
                  onTap: saving ? null : onOverride,
                  child: Text(
                    'Override and save anyway',
                    style: TextStyle(
                      color: AppColors.accentStrong,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticky save bar at bottom
// ---------------------------------------------------------------------------
class _SaveBar extends StatelessWidget {
  final bool canSave;
  final bool saving;
  final Future<void> Function() onSave;

  const _SaveBar({
    required this.canSave,
    required this.saving,
    required this.onSave,
  });

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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: saving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save Incomplete',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Customer visit-code result dialog (Story 13.3)
// Shows the system-generated code + free WhatsApp delivery. No SMS.
// ---------------------------------------------------------------------------
class _CustomerCodeDialog extends StatelessWidget {
  final String code;
  final String? whatsappLink;

  const _CustomerCodeDialog({required this.code, this.whatsappLink});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceBase,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Lead saved',
              style: GoogleFonts.fraunces(
                fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.inkPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Share this visit code with the customer. They show it at reception to verify their visit.',
              style: TextStyle(fontSize: 13, color: AppColors.inkSecondary, height: 1.5),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.mist,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: Center(
                child: Text(
                  code,
                  style: GoogleFonts.fraunces(
                    fontSize: 30, fontWeight: FontWeight.w600,
                    color: AppColors.accentStrong, letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy code'),
            ),
            if (whatsappLink != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentStrong,
                    foregroundColor: AppColors.surfaceBase,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final uri = Uri.parse(whatsappLink!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Send via WhatsApp'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
