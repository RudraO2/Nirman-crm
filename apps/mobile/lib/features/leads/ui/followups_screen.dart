// Story 3.5 — In-app Follow-up Calendar
// Lists all leads with upcoming next_followup_at sorted chronologically.
// Groups by date. Client-side filter from myLeadsProvider.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/lead_model.dart';
import '../providers/lead_providers.dart';
import 'lead_card.dart';

class FollowupsScreen extends ConsumerWidget {
  const FollowupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leadsAsync = ref.watch(myLeadsProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.inkPrimary),
        title: Text(
          'Plan',
          style: GoogleFonts.fraunces(
            fontSize: 21, fontWeight: FontWeight.w500, color: AppColors.inkPrimary,
          ),
        ),
      ),
      body: leadsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentStrong)),
        error: (_, __) => Center(child: Text('Could not load leads.', style: TextStyle(color: AppColors.inkSecondary))),
        data: (leads) {
          final upcoming = leads
              .where((l) => l.nextFollowupAt != null)
              .toList()
            ..sort((a, b) => a.nextFollowupAt!.compareTo(b.nextFollowupAt!));

          if (upcoming.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_available_rounded, size: 48, color: AppColors.inkDisabled),
                  const SizedBox(height: 12),
                  Text('No upcoming follow-ups', style: TextStyle(fontSize: 16, color: AppColors.inkPrimary, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text('Schedule follow-ups from a lead\'s detail screen', style: TextStyle(fontSize: 13, color: AppColors.inkSecondary)),
                ],
              ),
            );
          }

          // Group by calendar date
          final grouped = <String, List<LeadListItem>>{};
          for (final lead in upcoming) {
            final key = _dateKey(lead.nextFollowupAt!);
            grouped.putIfAbsent(key, () => []).add(lead);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: grouped.entries.map((entry) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 8),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: entry.key.startsWith('OVERDUE')
                            ? AppColors.statusHot
                            : AppColors.brass,
                      ),
                    ),
                  ),
                  ...entry.value.map((lead) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: LeadCard(
                      lead: lead,
                      onTap: () => context.push('/lead/${lead.id}'),
                    ),
                  )),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }

  static String _dateKey(DateTime dt) {
    final l   = dt.toLocal();
    final now = DateTime.now();
    final today    = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final day      = DateTime(l.year, l.month, l.day);
    if (day.isAtSameMomentAs(today))    return 'TODAY';
    if (day.isAtSameMomentAs(tomorrow)) return 'TOMORROW';
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final diff = day.difference(today).inDays;
    if (diff < 0) return 'OVERDUE · ${l.day} ${months[l.month]}';
    return '${l.day} ${months[l.month]} ${l.year}';
  }
}
