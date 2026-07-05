// Story 3.8 — Filtered lead list
// Shown when user taps a count tile in Today's Actions widget.
// Client-side filter from myLeadsProvider — no new RPC.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/lead_model.dart';
import '../providers/lead_providers.dart';
import 'lead_card.dart';

enum LeadFilter {
  followupsToday,
  visitsToday,
  incomplete,
  pendingOutcome,
  untouched,
}

extension LeadFilterExt on LeadFilter {
  String get title {
    switch (this) {
      case LeadFilter.followupsToday:  return 'Follow-ups Today';
      case LeadFilter.visitsToday:     return 'Visits Today';
      case LeadFilter.incomplete:      return 'Incomplete Leads';
      case LeadFilter.pendingOutcome:  return 'Calls Awaiting Outcome';
      case LeadFilter.untouched:       return 'Untouched Leads';
    }
  }

  String get emptyMessage {
    switch (this) {
      case LeadFilter.followupsToday:  return 'No follow-ups due today';
      case LeadFilter.visitsToday:     return 'No site visits scheduled today';
      case LeadFilter.incomplete:      return 'No incomplete leads';
      case LeadFilter.pendingOutcome:  return 'No calls awaiting outcome';
      case LeadFilter.untouched:       return 'No untouched leads — all worked!';
    }
  }

  List<LeadListItem> apply(List<LeadListItem> leads) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    bool sameDay(DateTime? dt) {
      if (dt == null) return false;
      final l = dt.toLocal();
      return DateTime(l.year, l.month, l.day).isAtSameMomentAs(today);
    }

    switch (this) {
      case LeadFilter.followupsToday:  return leads.where((l) => sameDay(l.nextFollowupAt)).toList();
      case LeadFilter.visitsToday:     return leads.where((l) => sameDay(l.visitDate)).toList();
      case LeadFilter.incomplete:      return leads.where((l) => l.isIncomplete).toList();
      case LeadFilter.pendingOutcome:  return leads.where((l) => l.hasPendingOutcome).toList();
      case LeadFilter.untouched:       return leads.where((l) => l.isUntouched).toList();
    }
  }
}

class FilteredLeadsScreen extends ConsumerWidget {
  final LeadFilter filter;
  const FilteredLeadsScreen({super.key, required this.filter});

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
          filter.title,
          style: GoogleFonts.fraunces(
            fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.inkPrimary,
          ),
        ),
      ),
      body: leadsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentStrong)),
        error: (_, __) => Center(child: Text('Could not load leads.', style: TextStyle(color: AppColors.inkSecondary))),
        data: (leads) {
          final filtered = filter.apply(leads);
          if (filtered.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 48, color: AppColors.inkDisabled),
                  const SizedBox(height: 12),
                  Text(filter.emptyMessage, style: TextStyle(fontSize: 15, color: AppColors.inkSecondary)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: filtered.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LeadCard(
                lead: filtered[i],
                onTap: () => context.push('/lead/${filtered[i].id}'),
              ),
            ),
          );
        },
      ),
    );
  }
}
