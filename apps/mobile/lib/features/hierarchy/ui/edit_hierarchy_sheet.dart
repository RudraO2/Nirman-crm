// Story 12.4-mobile — edit a user's tier + reporting line.
//
// A modal bottom sheet mirroring the admin EditDialog (hierarchy-client.tsx): a Tier
// dropdown; a Reports-to dropdown shown ONLY for ladder tiers (options filtered to
// strictly-higher ladder users via managerOptionsFor); an Agency dropdown shown ONLY
// for partner_agency. Client-validates partner-needs-agency; the RPC re-checks every
// rule server-side and its rejections map to calm messages via HierarchyException.friendly.
//
// Returns `true` via the sheet result on a successful save (caller invalidates the list).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/hierarchy_repository.dart';
import '../data/models/agency.dart';
import '../data/models/hierarchy_user.dart';

Future<bool?> showEditHierarchySheet(
  BuildContext context, {
  required HierarchyUser user,
  required List<HierarchyUser> users,
  required List<Agency> agencies,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surfaceRaised,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _EditHierarchySheet(
      user: user,
      users: users,
      agencies: agencies,
    ),
  );
}

class _EditHierarchySheet extends ConsumerStatefulWidget {
  final HierarchyUser user;
  final List<HierarchyUser> users;
  final List<Agency> agencies;

  const _EditHierarchySheet({
    required this.user,
    required this.users,
    required this.agencies,
  });

  @override
  ConsumerState<_EditHierarchySheet> createState() =>
      _EditHierarchySheetState();
}

class _EditHierarchySheetState extends ConsumerState<_EditHierarchySheet> {
  late RoleTier _tier;
  String? _reportsTo;
  String? _agencyId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tier = widget.user.roleTier == RoleTier.unknown
        ? RoleTier.frontLineRep
        : widget.user.roleTier;
    _reportsTo = widget.user.reportsToUserId;
    _agencyId = widget.user.agencyId;
  }

  bool get _isPartner => _tier == RoleTier.partnerAgency;

  List<HierarchyUser> get _managerOptions => managerOptionsFor(
        tier: _tier,
        editingUserId: widget.user.id,
        allUsers: widget.users,
      );

  void _onTierChanged(RoleTier? t) {
    if (t == null) return;
    setState(() {
      _tier = t;
      _error = null;
      // Drop a now-invalid manager selection when the tier changes.
      if (!_tier.isLadder) {
        _reportsTo = null;
      } else if (_reportsTo != null &&
          !_managerOptions.any((m) => m.id == _reportsTo)) {
        _reportsTo = null;
      }
      if (!_isPartner) _agencyId = null;
    });
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_isPartner && _agencyId == null) {
      setState(() => _error = 'Choose an agency for this partner user.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(hierarchyRepositoryProvider).setHierarchy(
            userId: widget.user.id,
            tier: _tier,
            reportsTo: _tier.isLadder ? _reportsTo : null,
            agencyId: _isPartner ? _agencyId : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on HierarchyException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.friendly;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Couldn\'t save the change. Please try again.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
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
            const SizedBox(height: 14),
            Text(
              widget.user.emailOrUsername,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.inkPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // Tier
            const _FieldLabel('Tier'),
            DropdownButtonFormField<RoleTier>(
              initialValue: _tier,
              decoration: _fieldDecoration(),
              items: RoleTier.selectable
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: _saving ? null : _onTierChanged,
            ),

            // Reports to (ladder tiers only)
            if (_tier.isLadder) ...[
              const SizedBox(height: 14),
              const _FieldLabel('Reports to'),
              DropdownButtonFormField<String?>(
                initialValue:
                    _managerOptions.any((m) => m.id == _reportsTo) ? _reportsTo : null,
                decoration: _fieldDecoration(),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('— None (top of tree) —'),
                  ),
                  ..._managerOptions.map((m) => DropdownMenuItem<String?>(
                        value: m.id,
                        child: Text('${m.emailOrUsername} · ${m.roleTier.label}',
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged:
                    _saving ? null : (v) => setState(() => _reportsTo = v),
              ),
              if (_managerOptions.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'No higher-tier users to report to yet.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.inkSecondary),
                  ),
                ),
            ],

            // Agency (partner only)
            if (_isPartner) ...[
              const SizedBox(height: 14),
              const _FieldLabel('Agency *'),
              DropdownButtonFormField<String?>(
                initialValue:
                    widget.agencies.any((a) => a.id == _agencyId) ? _agencyId : null,
                decoration: _fieldDecoration(hint: 'Select agency'),
                items: widget.agencies
                    .map((a) => DropdownMenuItem<String?>(
                        value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: _saving ? null : (v) => setState(() => _agencyId = v),
              ),
              if (widget.agencies.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'No agencies yet — create one first.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.inkSecondary),
                  ),
                ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentStrong,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surfaceSunk,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.inkSecondary,
        ),
      ),
    );
  }
}
