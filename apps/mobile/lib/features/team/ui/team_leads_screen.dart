// Story 12.6-mobile — Team leads screen (scoped by get_team_leads).
//
// Read-only monitoring view: lists the caller's visibility scope (leader=subtree,
// head=all, partner=agency-only, rep=self, receptionist=empty) with each lead's
// owner. Tapping opens the existing read-only lead detail. No mutation path.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/team_lead.dart';
import '../providers/team_providers.dart';

class TeamLeadsScreen extends ConsumerWidget {
  const TeamLeadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leadsAsync = ref.watch(teamLeadsProvider);
    final names = ref.watch(ownerNamesProvider).asData?.value ?? const {};

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Team leads',
          style: AppType.display(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            color: AppColors.inkPrimary,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(teamLeadsProvider);
          // Await so the spinner holds until data lands; swallow the error — the
          // `.when` error branch renders it. An unguarded throw would escape the
          // RefreshIndicator callback as an unhandled async error.
          try {
            await ref.read(teamLeadsProvider.future);
          } catch (_) {/* surfaced by the .when error branch */}
        },
        child: leadsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              SizedBox(height: 120),
              Center(
                child: Text("Couldn't load team leads. Pull to refresh.",
                    style: TextStyle(color: AppColors.inkSecondary)),
              ),
            ],
          ),
          data: (leads) {
            if (leads.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text('No team leads to show yet.',
                        style: TextStyle(color: AppColors.inkSecondary)),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: leads.length,
              itemBuilder: (_, i) => _TeamLeadRow(
                item: leads[i],
                owner: ownerLabel(leads[i].ownerId, names),
                onTap: () => context.push('/lead/${leads[i].id}'),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TeamLeadRow extends StatelessWidget {
  final TeamLead item;
  final String owner;
  final VoidCallback onTap;

  const _TeamLeadRow({
    required this.item,
    required this.owner,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lead = item.lead;
    final title = (lead.name?.isNotEmpty == true)
        ? lead.name!
        : (lead.phone?.isNotEmpty == true ? lead.displayPhone : 'Lead');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusPill(status: lead.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.person_outline_rounded,
                              size: 13, color: AppColors.inkDisabled),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              owner,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.inkDisabled),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: status.statusBgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.statusLabel,
        style: TextStyle(
          color: status.statusColor,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
