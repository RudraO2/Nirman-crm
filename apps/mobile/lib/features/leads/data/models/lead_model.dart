// Story 2.3 / 2.5 — Lead models for creation and list display.

class TimelineEntry {
  final String id;
  final String eventType;
  final String? actorName;
  final String? actorRole;
  final Map<String, dynamic> payload;
  final DateTime occurredAt;

  const TimelineEntry({
    required this.id,
    required this.eventType,
    this.actorName,
    this.actorRole,
    required this.payload,
    required this.occurredAt,
  });

  factory TimelineEntry.fromJson(Map<String, dynamic> j) => TimelineEntry(
        id: j['id'] as String,
        eventType: j['event_type'] as String,
        actorName: j['actor_name'] as String?,
        actorRole: j['actor_role'] as String?,
        payload: j['payload'] is Map
            ? Map<String, dynamic>.from(j['payload'] as Map)
            : <String, dynamic>{},
        occurredAt: DateTime.parse(j['occurred_at'] as String),
      );
}

class LeadCreationResult {
  final String leadId;
  final bool isIncomplete;

  const LeadCreationResult({
    required this.leadId,
    required this.isIncomplete,
  });

  factory LeadCreationResult.fromJson(Map<String, dynamic> json) {
    return LeadCreationResult(
      leadId: json['lead_id'] as String,
      isIncomplete: json['is_incomplete'] as bool,
    );
  }
}

// ── Story 2.5 — Lead list item returned by get_my_leads() RPC ─────────────

class LeadListItem {
  final String id;
  final String status;
  final String? name;
  final String? phone;
  final String? source;
  final String? propertyType;
  final String? location;
  final int? budgetMin;
  final int? budgetMax;
  final String? ticketSize;
  final DateTime? visitDate;
  final DateTime? nextFollowupAt;
  final bool isIncomplete;
  final DateTime? pendingOutcomeAt;
  final DateTime? lastActionAt;
  final DateTime createdAt;
  final int urgencyScore;
  final String? interestType;
  /// Story 2.8 — populated by get_my_archived_leads; null for active-list rows.
  final DateTime? archivedAt;

  const LeadListItem({
    required this.id,
    required this.status,
    this.name,
    this.phone,
    this.source,
    this.propertyType,
    this.location,
    this.budgetMin,
    this.budgetMax,
    this.ticketSize,
    this.visitDate,
    this.nextFollowupAt,
    required this.isIncomplete,
    this.pendingOutcomeAt,
    this.lastActionAt,
    required this.createdAt,
    required this.urgencyScore,
    this.interestType,
    this.archivedAt,
  });

  factory LeadListItem.fromJson(Map<String, dynamic> j) {
    DateTime? _dt(String? s) => s == null ? null : DateTime.parse(s);
    return LeadListItem(
      id:                j['id'] as String,
      status:            j['status'] as String,
      name:              j['name'] as String?,
      phone:             j['phone'] as String?,
      source:            j['source'] as String?,
      propertyType:      j['property_type'] as String?,
      location:          j['location'] as String?,
      budgetMin:         j['budget_min'] as int?,
      budgetMax:         j['budget_max'] as int?,
      ticketSize:        j['ticket_size'] as String?,
      visitDate:         _dt(j['visit_date'] as String?),
      nextFollowupAt:    _dt(j['next_followup_at'] as String?),
      isIncomplete:      j['is_incomplete'] as bool,
      pendingOutcomeAt:  _dt(j['pending_outcome_at'] as String?),
      lastActionAt:      _dt(j['last_action_at'] as String?),
      createdAt:         DateTime.parse(j['created_at'] as String),
      urgencyScore:      j['urgency_score'] as int,
      interestType:      j['interest_type'] as String?,
      archivedAt:        _dt(j['archived_at'] as String?),
    );
  }

  bool get isStale =>
      lastActionAt != null &&
      DateTime.now().difference(lastActionAt!).inDays >= 7;

  bool get hasPendingOutcome => pendingOutcomeAt != null;

  bool get hasOverdueFollowup =>
      nextFollowupAt != null && nextFollowupAt!.isBefore(DateTime.now());

  // Formats raw 10-digit phone as "98765 43210"
  String get displayPhone {
    if (phone == null || phone!.length < 10) return phone ?? '';
    return '${phone!.substring(0, 5)} ${phone!.substring(5)}';
  }
}

// ── Story 2.4 — Full lead detail (includes project_ids for edit pre-fill) ──

class LeadDetail extends LeadListItem {
  final List<String> projectIds;
  final String? remarks;

  const LeadDetail({
    required super.id,
    required super.status,
    super.name,
    super.phone,
    super.source,
    super.propertyType,
    super.location,
    super.budgetMin,
    super.budgetMax,
    super.ticketSize,
    super.visitDate,
    super.nextFollowupAt,
    required super.isIncomplete,
    super.pendingOutcomeAt,
    super.lastActionAt,
    required super.createdAt,
    required super.urgencyScore,
    super.interestType,
    required this.projectIds,
    this.remarks,
  });

  factory LeadDetail.fromJson(Map<String, dynamic> j) {
    final base = LeadListItem.fromJson(j);
    final rawPids = j['project_ids'];
    final pids = rawPids is List
        ? rawPids.map((e) => e.toString()).toList()
        : <String>[];
    return LeadDetail(
      id: base.id, status: base.status, name: base.name, phone: base.phone,
      source: base.source, propertyType: base.propertyType, location: base.location,
      budgetMin: base.budgetMin, budgetMax: base.budgetMax, ticketSize: base.ticketSize,
      visitDate: base.visitDate, nextFollowupAt: base.nextFollowupAt,
      isIncomplete: base.isIncomplete, pendingOutcomeAt: base.pendingOutcomeAt,
      lastActionAt: base.lastActionAt, createdAt: base.createdAt,
      urgencyScore: base.urgencyScore, interestType: base.interestType,
      projectIds: pids,
      remarks: j['remarks'] as String?,
    );
  }
}

// Payload for updating an existing lead (Story 2.4)
class UpdateLeadPayload {
  final String leadId;
  final String status;
  final String phone;
  final String? source;
  final String? name;
  final String? propertyType;
  final String? location;
  final int? budgetMin;
  final int? budgetMax;
  final String? ticketSize;
  final String? remarks;
  final String? visitDate;
  final String? nextFollowupAt;
  final String? interestType;
  final List<String> projectIds;

  const UpdateLeadPayload({
    required this.leadId,
    required this.status,
    required this.phone,
    this.source,
    this.name,
    this.propertyType,
    this.location,
    this.budgetMin,
    this.budgetMax,
    this.ticketSize,
    this.remarks,
    this.visitDate,
    this.nextFollowupAt,
    this.interestType,
    this.projectIds = const [],
  });

  Map<String, dynamic> toJson() => {
    'lead_id': leadId,
    'status': status,
    'phone': phone,
    if (source != null) 'source': source,
    if (name != null) 'name': name,
    if (propertyType != null) 'property_type': propertyType,
    if (location != null) 'location': location,
    if (budgetMin != null) 'budget_min': budgetMin,
    if (budgetMax != null) 'budget_max': budgetMax,
    if (ticketSize != null) 'ticket_size': ticketSize,
    if (remarks != null) 'remarks': remarks,
    if (visitDate != null) 'visit_date': visitDate,
    if (nextFollowupAt != null) 'next_followup_at': nextFollowupAt,
    if (interestType != null) 'interest_type': interestType,
    'project_ids': projectIds,
  };
}

class UpdateLeadResult {
  final String leadId;
  final bool isIncomplete;
  final String status;
  final List<String> changedFields;

  const UpdateLeadResult({
    required this.leadId,
    required this.isIncomplete,
    required this.status,
    required this.changedFields,
  });

  factory UpdateLeadResult.fromJson(Map<String, dynamic> j) {
    return UpdateLeadResult(
      leadId:        j['lead_id'] as String,
      isIncomplete:  j['is_incomplete'] as bool,
      status:        j['status'] as String,
      changedFields: (j['changed_fields'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

// ── Story 2.7 — Mark Dead result (carries previous status for undo) ───────

class MarkDeadResult {
  final String previousStatus;

  const MarkDeadResult({required this.previousStatus});

  factory MarkDeadResult.fromJson(Map<String, dynamic> j) {
    return MarkDeadResult(previousStatus: j['previous_status'] as String);
  }
}

// ── Story 2.6 — Reschedule visit result ───────────────────────────────────

class RescheduleVisitResult {
  final int rescheduleCount;
  final DateTime visitDate;

  const RescheduleVisitResult({
    required this.rescheduleCount,
    required this.visitDate,
  });

  factory RescheduleVisitResult.fromJson(Map<String, dynamic> j) {
    return RescheduleVisitResult(
      rescheduleCount: j['reschedule_count'] as int,
      visitDate: DateTime.parse(j['visit_date'] as String),
    );
  }
}

// ── Story 3.3 / 3.4 — WhatsApp template ──────────────────────────────────

class WhatsAppTemplate {
  final String id;
  final String name;
  final String body;

  const WhatsAppTemplate({
    required this.id,
    required this.name,
    required this.body,
  });

  factory WhatsAppTemplate.fromJson(Map<String, dynamic> j) {
    return WhatsAppTemplate(
      id:   j['id'] as String,
      name: j['name'] as String,
      body: j['body'] as String,
    );
  }

  // Substitutes {{variable}} placeholders with lead data.
  String render({
    String? name,
    String? propertyType,
    String? ticketSize,
    String? budget,
    String? projects,
  }) {
    return body
        .replaceAll('{{name}}',          name          ?? '[Not set]')
        .replaceAll('{{property_type}}', propertyType  ?? '[Not set]')
        .replaceAll('{{ticket_size}}',   ticketSize    ?? '[Not set]')
        .replaceAll('{{budget}}',        budget        ?? '[Not set]')
        .replaceAll('{{project}}',       projects      ?? '[Not set]');
  }
}

// ── Project reference (lead form project picker) ───────────────────────────

class ProjectRef {
  final String id;
  final String name;

  const ProjectRef({required this.id, required this.name});

  factory ProjectRef.fromJson(Map<String, dynamic> json) {
    return ProjectRef(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}
