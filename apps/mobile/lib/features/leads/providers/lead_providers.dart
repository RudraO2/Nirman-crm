import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/lead_repository.dart';
import '../data/models/lead_model.dart';

part 'lead_providers.g.dart';

/// Single lead by ID with PII decrypted + project_ids (Story 2.4).
/// Returns null if not found / not owned by caller.
@riverpod
Future<LeadDetail?> leadById(LeadByIdRef ref, String id) {
  return ref.read(leadRepositoryProvider).getLeadById(id);
}

/// Urgency-sorted active leads for the current user (Story 2.5).
/// Invalidate this provider after any lead mutation to refresh the list.
@riverpod
Future<List<LeadListItem>> myLeads(MyLeadsRef ref) {
  return ref.read(leadRepositoryProvider).getMyLeads();
}

/// Available projects for the lead form project picker.
@riverpod
Future<List<ProjectRef>> availableProjects(AvailableProjectsRef ref) {
  return ref.watch(leadRepositoryProvider).fetchProjects();
}

/// Timeline events for a lead (FR-19).
@riverpod
Future<List<TimelineEntry>> leadTimeline(LeadTimelineRef ref, String id) {
  return ref.watch(leadRepositoryProvider).getLeadTimeline(id);
}
