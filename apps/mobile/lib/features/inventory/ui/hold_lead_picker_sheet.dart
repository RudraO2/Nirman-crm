// Story 15.2-mobile — pick a lead to hold a unit for.
//
// Uses teamLeadsProvider (get_team_leads, migration 0060) rather than
// myLeadsProvider so the candidate set matches EXACTLY what the hold_unit RPC
// will accept, scoped by visible_user_ids():
//   builder_head / super_admin → every internal lead
//   team_leader                → own + reporting subtree
//   front_line_rep             → self only
// (A rep's own owned leads are identical to before; only peer-SHARED leads drop
// out — and hold_unit rejects those anyway, so nothing holdable is lost.)
// Because multiple owners' leads can now appear, each row shows the owner label
// (ownerNamesProvider — bounded to the owners actually returned). Returns the
// chosen LeadListItem via the sheet result, or null if dismissed. The RPC still
// enforces authority; this list only narrows the picker to plausible candidates.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../leads/data/models/lead_model.dart';
import '../../team/data/models/team_lead.dart';
import '../../team/providers/team_providers.dart';

Future<LeadListItem?> showHoldLeadPicker(BuildContext context) {
  return showModalBottomSheet<LeadListItem>(
    context: context,
    backgroundColor: AppColors.surfaceRaised,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.75,
      child: _HoldLeadPicker(),
    ),
  );
}

class _HoldLeadPicker extends ConsumerStatefulWidget {
  const _HoldLeadPicker();

  @override
  ConsumerState<_HoldLeadPicker> createState() => _HoldLeadPickerState();
}

class _HoldLeadPickerState extends ConsumerState<_HoldLeadPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final leadsAsync = ref.watch(teamLeadsProvider);
    final ownerNames = ref.watch(ownerNamesProvider).valueOrNull ?? const {};

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
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
            const Text(
              'Hold for which lead?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.inkPrimary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search name or phone',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: AppColors.surfaceSunk,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: leadsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(
                  child: Text("Couldn't load leads.",
                      style: TextStyle(color: AppColors.inkSecondary)),
                ),
                data: (leads) {
                  final filtered = _filter(leads, _query);
                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('No matching leads.',
                          style: TextStyle(color: AppColors.inkSecondary)),
                    );
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.line),
                    itemBuilder: (_, i) {
                      final t = filtered[i];
                      final l = t.lead;
                      final owner = ownerLabel(t.ownerId, ownerNames);
                      final phone = l.phone;
                      final subtitle = phone != null && phone.isNotEmpty
                          ? '$phone · $owner'
                          : owner;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l.name?.isNotEmpty == true ? l.name! : (l.phone ?? 'Lead'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkPrimary,
                          ),
                        ),
                        subtitle: Text(subtitle,
                            style: const TextStyle(
                                color: AppColors.inkSecondary, fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: AppColors.inkDisabled),
                        onTap: () => Navigator.of(context).pop(l),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<TeamLead> _filter(List<TeamLead> leads, String q) {
    if (q.isEmpty) return leads;
    return leads.where((t) {
      final name = (t.lead.name ?? '').toLowerCase();
      final phone = (t.lead.phone ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }
}
