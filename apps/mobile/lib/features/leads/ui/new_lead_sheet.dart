// Story 2.3 — Status-first New Lead bottom sheet
// UX spec: EXPERIENCE.md §Component Patterns → "Status-first new-lead sheet"
//   Step 1: Full-screen Status grid (6 options, large touch targets, no other fields)
//   Step 2: Phone field auto-focused + optional fields + "Save Incomplete" CTA
// Accessibility: WCAG 2.1 AA, ≥48dp tap targets, color NOT only signal

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
      await ref.read(leadRepositoryProvider).createLead(payload);
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
  // Build
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return _status == null ? _buildStatusPicker() : _buildForm();
  }

  // ------------------------------------------------------------------
  // Step 1: Status picker
  // ------------------------------------------------------------------
  Widget _buildStatusPicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderHairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'New Lead',
            style: GoogleFonts.sourceSerif4(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: AppColors.inkPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose a status to start',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.inkSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          // 2-column grid of status cards
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.2,
            children: const [
              'hot', 'warm', 'cold', 'future', 'sold', 'dead',
            ].map((s) => _StatusCard(
              status: s,
              onTap: () => setState(() => _status = s),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Step 2: Lead form
  // ------------------------------------------------------------------
  Widget _buildForm() {
    final statusColor = _status!.statusColor;
    final statusLabel = _status!.statusLabel;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (_, scrollCtrl) {
        return Column(
          children: [
            // Header — fixed, not scrollable
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              color: AppColors.surfaceBase,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderHairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _status = null),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Icon(Icons.arrow_back_ios_new_rounded,
                              size: 16, color: AppColors.inkSecondary),
                            const SizedBox(width: 4),
                            Text('Status',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.inkSecondary,
                              )),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Status pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(color: AppColors.borderHairline, height: 1),
                ],
              ),
            ),
            // Scrollable form body
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                children: [
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
// Step 1 — Status card
// ---------------------------------------------------------------------------
class _StatusCard extends StatelessWidget {
  final String status;
  final VoidCallback onTap;

  const _StatusCard({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = status.statusColor;
    final label = status.statusLabel;

    return Semantics(
      button: true,
      label: '$label status',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.35), width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                  letterSpacing: 0.1,
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
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.24 * 11.5,
            color: AppColors.inkSecondary,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          Text('*', style: TextStyle(color: AppColors.error, fontSize: 12)),
        ],
      ],
    );
  }
}

InputDecoration _inputDecoration({String? hint, String? errorText}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.inkDisabled, fontSize: 16),
    errorText: errorText,
    errorStyle: TextStyle(color: AppColors.error, fontSize: 12),
    filled: true,
    fillColor: AppColors.surfaceSunk,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.borderHairline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.borderHairline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.accentStrong, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isActive ? AppColors.accentStrong.withOpacity(0.12) : AppColors.surfaceSunk,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isActive ? AppColors.accentStrong : AppColors.borderHairline,
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Text(
              e.value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? AppColors.accentStrong : AppColors.inkPrimary,
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.navy.withOpacity(0.10) : AppColors.surfaceSunk,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? AppColors.navy : AppColors.borderHairline,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (active) ...[
                      Icon(Icons.check_rounded, size: 14, color: AppColors.navy),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? AppColors.navy : AppColors.inkPrimary,
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
                backgroundColor: AppColors.accentStrong,
                foregroundColor: AppColors.surfaceBase,
                disabledBackgroundColor: AppColors.surfaceMist,
                disabledForegroundColor: AppColors.inkDisabled,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: saving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(AppColors.surfaceBase),
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
