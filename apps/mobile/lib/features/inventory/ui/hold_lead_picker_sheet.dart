// Story 15.2-mobile — pick one of the caller's own leads to hold a unit for.
//
// Reuses myLeadsProvider (the caller's active leads) — no new query. Returns the
// chosen LeadListItem via the sheet result, or null if dismissed. The RPC enforces
// ownership; this list is already scoped to the caller's leads.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../leads/data/models/lead_model.dart';
import '../../leads/providers/lead_providers.dart';

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
    final leadsAsync = ref.watch(myLeadsProvider);

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
                  child: Text("Couldn't load your leads.",
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
                      final l = filtered[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l.name?.isNotEmpty == true ? l.name! : (l.phone ?? 'Lead'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkPrimary,
                          ),
                        ),
                        subtitle: l.phone != null
                            ? Text(l.phone!,
                                style: const TextStyle(
                                    color: AppColors.inkSecondary, fontSize: 12))
                            : null,
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

  static List<LeadListItem> _filter(List<LeadListItem> leads, String q) {
    if (q.isEmpty) return leads;
    return leads.where((l) {
      final name = (l.name ?? '').toLowerCase();
      final phone = (l.phone ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }
}
