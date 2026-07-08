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
  // Story 13.3 — system-generated visit code + free WhatsApp delivery link.
  final String? customerCode;
  final String? whatsappLink;

  const LeadCreationResult({
    required this.leadId,
    required this.isIncomplete,
    this.customerCode,
    this.whatsappLink,
  });

  factory LeadCreationResult.fromJson(Map<String, dynamic> json) {
    return LeadCreationResult(
      leadId: json['lead_id'] as String,
      isIncomplete: json['is_incomplete'] as bool,
      customerCode: json['customer_code'] as String?,
      whatsappLink: json['whatsapp_link'] as String?,
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
  /// Story 4.4 — true when this lead was shared with the caller (not owned).
  final bool isShared;

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
    this.isShared = false,
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
      isShared:          j['is_shared'] as bool? ?? false,
    );
  }

  bool get isStale =>
      lastActionAt != null &&
      DateTime.now().difference(lastActionAt!).inDays >= 7;

  /// True when the lead has had no action since it was created — e.g. bulk-imported
  /// and never worked. `last_action_at` is stamped equal to `created_at` on insert;
  /// any real action (call, status change, remark, follow-up, reschedule) advances
  /// it. A 2-second tolerance absorbs insert-time clock skew between the two columns.
  /// Pending-outcome leads are excluded — a call already advanced last_action_at.
  bool get isUntouched =>
      !hasPendingOutcome &&
      (lastActionAt == null ||
          !lastActionAt!.isAfter(createdAt.add(const Duration(seconds: 2))));

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
    super.isShared,
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
      isShared: base.isShared,
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

  /// Story 11.2/11.3 — the single token catalog. Must stay identical to the
  /// variable-chip list in apps/admin/src/app/(app)/templates.
  static const List<String> tokenCatalog = [
    'name', 'phone', 'project', 'property_type',
    'ticket_size', 'budget', 'status', 'followup_date',
    'agent_name', // the logged-in sender (derived from their username)
  ];

  // Substitutes {{variable}} placeholders with lead data (Story 11.3).
  // Null/empty values render as "—"; unknown {{tokens}} are stripped so the
  // composed message never carries raw braces.
  String render({
    String? name,
    String? phone,
    String? propertyType,
    String? ticketSize,
    String? budget,
    String? projects,
    String? status,
    String? followupDate,
    String? agentName,
  }) {
    final values = <String, String?>{
      'name':          name,
      'phone':         phone,
      'project':       projects,
      'property_type': propertyType,
      'ticket_size':   ticketSize,
      'budget':        budget,
      'status':        status,
      'followup_date': followupDate,
      'agent_name':    agentName,
    };
    var out = body;
    for (final token in tokenCatalog) {
      final v = values[token];
      out = out.replaceAll('{{$token}}', (v == null || v.isEmpty) ? '—' : v);
    }
    return out.replaceAll(RegExp(r'\{\{[a-zA-Z_]+\}\}'), '').trim();
  }
}

// ── Story 4.4 — Active share entry (owned-lead detail view) ──────────────────

class LeadShareEntry {
  final String id;
  final String recipientUserId;
  final String recipientUsername;
  final DateTime grantedAt;

  const LeadShareEntry({
    required this.id,
    required this.recipientUserId,
    required this.recipientUsername,
    required this.grantedAt,
  });

  factory LeadShareEntry.fromJson(Map<String, dynamic> j) => LeadShareEntry(
        id:                j['id'] as String,
        recipientUserId:   j['recipient_user_id'] as String,
        recipientUsername: j['recipient_username'] as String? ?? j['recipient_user_id'] as String,
        grantedAt:         DateTime.parse(j['granted_at'] as String),
      );
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

// ── Story 4.4 — Employee reference for share picker ───────────────────────

class EmployeeRef {
  final String id;
  final String username;

  const EmployeeRef({required this.id, required this.username});

  factory EmployeeRef.fromJson(Map<String, dynamic> j) => EmployeeRef(
        id:       j['id'] as String,
        username: j['username'] as String,
      );
}
