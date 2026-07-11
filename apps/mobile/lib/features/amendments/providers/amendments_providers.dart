// Story 16.2-mobile — amendments providers.
//
// Family keyed on the status-filter db value ('' = all). Invalidate after a status
// change or a team-join so the surface refetches through the RPC (authoritative).

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/amendments_repository.dart';
import '../data/models/execution_amendment.dart';

part 'amendments_providers.g.dart';

/// Execution-team amendments, optionally filtered to [statusFilter] (db value; ''=all).
@riverpod
Future<List<ExecutionAmendment>> amendmentsForExecution(
  AmendmentsForExecutionRef ref,
  String statusFilter,
) {
  final status =
      statusFilter.isEmpty ? null : AmendmentStatus.fromDb(statusFilter);
  return ref
      .watch(amendmentsRepositoryProvider)
      .getAmendmentsForExecution(status: status);
}
