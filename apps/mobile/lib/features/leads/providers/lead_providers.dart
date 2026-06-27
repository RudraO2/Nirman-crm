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
  return ref.read(leadRepositoryProvider).getAllMyLeads();
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

/// Caller's archived leads (dead/sold/future), filtered by [query] (Story 2.8).
/// Family keyed on query so debounced search updates the cache key cleanly.
@riverpod
Future<List<LeadListItem>> archivedLeads(ArchivedLeadsRef ref, String query) {
  return ref.watch(leadRepositoryProvider).getMyArchivedLeads(query: query);
}

/// Active share entries for [id] — owned-lead detail view (Story 4.4).
/// Invalidate after share/revoke to refresh chips.
@riverpod
Future<List<LeadShareEntry>> leadShares(LeadSharesRef ref, String id) {
  return ref.watch(leadRepositoryProvider).getLeadShares(id);
}

/// Active employees in caller's tenant for the share picker (Story 4.4).
@riverpod
Future<List<EmployeeRef>> employeesForShare(EmployeesForShareRef ref) {
  return ref.watch(leadRepositoryProvider).listEmployeesForShare();
}
