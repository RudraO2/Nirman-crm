// Story 16.2-mobile — an amendment row from get_amendments_for_execution.
//
// PII-MINIMIZED by design (matches the RPC): unit_no / configuration / description /
// status only — NO lead name or phone. Flutter-free so it stays unit-testable.

/// The amendment lifecycle (matches public.amendment_status + set_amendment_status).
enum AmendmentStatus {
  requested,
  acknowledged,
  inProgress,
  done,
  rejected;

  String get dbValue {
    switch (this) {
      case AmendmentStatus.inProgress:
        return 'in_progress';
      default:
        return name;
    }
  }

  String get label {
    switch (this) {
      case AmendmentStatus.requested:
        return 'Requested';
      case AmendmentStatus.acknowledged:
        return 'Acknowledged';
      case AmendmentStatus.inProgress:
        return 'In progress';
      case AmendmentStatus.done:
        return 'Done';
      case AmendmentStatus.rejected:
        return 'Rejected';
    }
  }

  bool get isTerminal =>
      this == AmendmentStatus.done || this == AmendmentStatus.rejected;

  /// Allowed next statuses, mirroring the RPC's validated transitions:
  /// requested→acknowledged; acknowledged→in_progress; in_progress→done; and
  /// →rejected from any non-terminal state.
  List<AmendmentStatus> get nextStatuses {
    switch (this) {
      case AmendmentStatus.requested:
        return const [AmendmentStatus.acknowledged, AmendmentStatus.rejected];
      case AmendmentStatus.acknowledged:
        return const [AmendmentStatus.inProgress, AmendmentStatus.rejected];
      case AmendmentStatus.inProgress:
        return const [AmendmentStatus.done, AmendmentStatus.rejected];
      case AmendmentStatus.done:
      case AmendmentStatus.rejected:
        return const [];
    }
  }

  static AmendmentStatus fromDb(String? v) {
    switch (v) {
      case 'acknowledged':
        return AmendmentStatus.acknowledged;
      case 'in_progress':
        return AmendmentStatus.inProgress;
      case 'done':
        return AmendmentStatus.done;
      case 'rejected':
        return AmendmentStatus.rejected;
      case 'requested':
      default:
        return AmendmentStatus.requested;
    }
  }
}

class ExecutionAmendment {
  final String amendmentId;
  final String unitId;
  final String unitNo;
  final String? configuration;
  final String leadId;
  final String description;
  final AmendmentStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ExecutionAmendment({
    required this.amendmentId,
    required this.unitId,
    required this.unitNo,
    this.configuration,
    required this.leadId,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExecutionAmendment.fromJson(Map<String, dynamic> j) =>
      ExecutionAmendment(
        amendmentId: j['amendment_id'] as String,
        unitId: j['unit_id'] as String,
        unitNo: j['unit_no'] as String,
        configuration: j['configuration'] as String?,
        leadId: j['lead_id'] as String,
        description: j['description'] as String,
        status: AmendmentStatus.fromDb(j['status'] as String?),
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );
}
