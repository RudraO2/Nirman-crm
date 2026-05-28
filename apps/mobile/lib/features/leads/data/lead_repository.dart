import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/lead_model.dart';

part 'lead_repository.g.dart';

/// Payload for creating a new lead (Story 2.3).
/// All fields except status and phone are optional (Quick-Capture pattern).
class CreateLeadPayload {
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
  final bool overrideDuplicate;

  const CreateLeadPayload({
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
    this.overrideDuplicate = false,
  });

  Map<String, dynamic> toJson() => {
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
    'override_duplicate': overrideDuplicate,
  };
}

/// Duplicate error detail returned by create-lead when phone already exists.
class DuplicateLeadError implements Exception {
  final String message;
  final String existingLeadId;
  final String ownerName;

  const DuplicateLeadError({
    required this.message,
    required this.existingLeadId,
    required this.ownerName,
  });

  @override
  String toString() => message;
}

class LeadRepository {
  final SupabaseClient _supabase;

  const LeadRepository(this._supabase);

  // Parses FunctionException.details → throws DuplicateLeadError or Exception.
  // supabase_flutter 2.x throws FunctionException on 4xx/5xx; details is decoded JSON.
  static Never _throwFromEdgeError(dynamic details, String fallback) {
    final body = details is Map ? Map<String, dynamic>.from(details as Map) : null;
    final err  = body?['error'] as Map<String, dynamic>?;
    final code = err?['code'] as String? ?? 'internal_error';
    final msg  = err?['message'] as String? ?? fallback;
    if (code == 'duplicate_lead') {
      final d = err?['details'] as Map<String, dynamic>?;
      throw DuplicateLeadError(
        message: msg,
        existingLeadId: d?['existing_lead_id'] as String? ?? '',
        ownerName: d?['owner'] as String? ?? 'another employee',
      );
    }
    throw Exception(msg);
  }

  /// Creates a new lead via the create-lead Edge Function.
  /// Throws [DuplicateLeadError] if phone already exists and override is false.
  /// Throws [Exception] on validation or server errors.
  Future<LeadCreationResult> createLead(CreateLeadPayload payload) async {
    try {
      final response = await _supabase.functions.invoke(
        'create-lead',
        body: payload.toJson(),
      );
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return LeadCreationResult.fromJson(data);
    } on DuplicateLeadError {
      rethrow;
    } on FunctionException catch (e) {
      _throwFromEdgeError(e.details, 'Failed to create lead');
    }
  }

  /// Fetches a single lead by ID (PII decrypted, includes project_ids).
  /// Returns null if not found or not owned by caller.
  Future<LeadDetail?> getLeadById(String leadId) async {
    final result = await _supabase.rpc(
      'get_lead_by_id',
      params: {'p_lead_id': leadId},
    );
    final rows = result as List;
    if (rows.isEmpty) return null;
    return LeadDetail.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Updates an existing lead via the update-lead Edge Function.
  /// Throws [DuplicateLeadError] on phone collision.
  /// Throws [Exception] on validation or server errors.
  Future<UpdateLeadResult> updateLead(UpdateLeadPayload payload) async {
    try {
      final response = await _supabase.functions.invoke(
        'update-lead',
        body: payload.toJson(),
      );
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return UpdateLeadResult.fromJson(data);
    } on DuplicateLeadError {
      rethrow;
    } on FunctionException catch (e) {
      _throwFromEdgeError(e.details, 'Failed to update lead');
    }
  }

  /// Returns urgency-sorted active leads for the current user.
  /// Calls the get_my_leads() SECURITY DEFINER RPC which decrypts PII server-side.
  Future<List<LeadListItem>> getMyLeads({int limit = 100, int offset = 0}) async {
    final result = await _supabase.rpc(
      'get_my_leads',
      params: {'p_limit': limit, 'p_offset': offset},
    );
    return (result as List)
        .map((row) => LeadListItem.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Caller's archived leads (Story 2.8). status ∈ (dead, sold, future), newest-archived first.
  /// [query] optional name substring OR exact-phone search.
  Future<List<LeadListItem>> getMyArchivedLeads({
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    final result = await _supabase.rpc(
      'get_my_archived_leads',
      params: {
        'p_q': (query == null || query.trim().isEmpty) ? null : query.trim(),
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return (result as List)
        .map((row) => LeadListItem.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// Quick Mark Dead — sets status='dead', returns previous status for undo (Story 2.7).
  Future<MarkDeadResult> markLeadDead(String leadId) async {
    final result = await _supabase.rpc(
      'mark_lead_dead',
      params: {'p_lead_id': leadId},
    );
    return MarkDeadResult.fromJson(result as Map<String, dynamic>);
  }

  /// Restores a lead to its previous status after undo (Story 2.7).
  Future<void> restoreLead(String leadId, String previousStatus) async {
    await _supabase.rpc(
      'restore_lead',
      params: {'p_lead_id': leadId, 'p_restore_status': previousStatus},
    );
  }

  /// Reschedules the visit date for a lead (Story 2.6).
  /// Increments reschedule_count and logs visit_rescheduled timeline event.
  Future<RescheduleVisitResult> rescheduleVisit(String leadId, DateTime newDate) async {
    final result = await _supabase.rpc(
      'reschedule_visit',
      params: {
        'p_lead_id': leadId,
        'p_new_visit_date': newDate.toUtc().toIso8601String(),
      },
    );
    return RescheduleVisitResult.fromJson(result as Map<String, dynamic>);
  }

  /// Sets pending_outcome_at on the lead and logs call_initiated (Story 3.1).
  Future<void> initiateCall(String leadId) async {
    await _supabase.rpc('initiate_call', params: {'p_lead_id': leadId});
  }

  /// Submits call outcome: updates status, appends remarks, optionally sets follow-up (Story 3.2).
  Future<void> submitCallOutcome({
    required String leadId,
    required String newStatus,
    String? remarks,
    DateTime? followupAt,
  }) async {
    await _supabase.rpc('submit_call_outcome', params: {
      'p_lead_id':     leadId,
      'p_new_status':  newStatus,
      if (remarks != null)    'p_remarks':     remarks,
      if (followupAt != null) 'p_followup_at': followupAt.toUtc().toIso8601String(),
    });
  }

  /// Clears pending_outcome_at with no status change (Story 3.2 "Didn't actually call").
  Future<void> clearPendingOutcome(String leadId) async {
    await _supabase.rpc('clear_pending_outcome', params: {'p_lead_id': leadId});
  }

  /// Sets follow-up date; logs followup_set or followup_rescheduled (Story 3.5).
  Future<void> setFollowup(String leadId, DateTime at) async {
    await _supabase.rpc('set_followup', params: {
      'p_lead_id': leadId,
      'p_at':      at.toUtc().toIso8601String(),
    });
  }

  /// Fetches active WhatsApp templates for this tenant (Story 3.4).
  Future<List<WhatsAppTemplate>> fetchWhatsAppTemplates() async {
    final result = await _supabase
        .from('whatsapp_templates')
        .select('id, name, body')
        .order('created_at');
    return (result as List)
        .map((r) => WhatsAppTemplate.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Logs a whatsapp_sent timeline event (Story 3.4).
  Future<void> logWhatsAppSent({
    required String leadId,
    required String templateName,
    required String renderedBody,
    required String recipientPhone,
  }) async {
    await _supabase.rpc('log_timeline_event', params: {
      'p_lead_id':    leadId,
      'p_event_type': 'whatsapp_sent',
      'p_payload': {
        'template_name':  templateName,
        'rendered_body':  renderedBody,
        'recipient_phone': recipientPhone,
      },
    });
  }

  /// Fetches lead timeline events (FR-19). Newest first, max 200.
  Future<List<TimelineEntry>> getLeadTimeline(String leadId) async {
    final result = await _supabase.rpc(
      'get_lead_timeline',
      params: {'p_lead_id': leadId},
    );
    return (result as List)
        .map((row) => TimelineEntry.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// Fetches the active project list for the lead form project picker.
  Future<List<ProjectRef>> fetchProjects() async {
    final result = await _supabase
        .from('projects')
        .select('id, name')
        .eq('is_active', true)
        .order('name');

    return (result as List)
        .map((row) => ProjectRef.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Shares a lead with another employee (Story 4.4). Idempotent.
  Future<void> shareLead(String leadId, String recipientUserId) async {
    await _supabase.rpc('share_lead', params: {
      'p_lead_id':            leadId,
      'p_recipient_user_id':  recipientUserId,
    });
  }

  /// Revokes a share (Story 4.4). Idempotent — no-op if share already gone.
  Future<void> revokeLead(String leadId, String recipientUserId) async {
    await _supabase.rpc('revoke_share', params: {
      'p_lead_id':            leadId,
      'p_recipient_user_id':  recipientUserId,
    });
  }

  /// Active share entries for [leadId] with recipient username (Story 4.4).
  /// Uses PostgREST FK join; tenant RLS ensures only caller's tenant rows.
  Future<List<LeadShareEntry>> getLeadShares(String leadId) async {
    final result = await _supabase
        .from('lead_shares')
        .select(
          'id, recipient_user_id, granted_at, '
          'recipient:users!lead_shares_recipient_user_id_fkey(email_or_username)',
        )
        .eq('lead_id', leadId)
        .order('granted_at');

    return (result as List).map((row) {
      final r = Map<String, dynamic>.from(row as Map);
      final recipientObj = r['recipient'] as Map<String, dynamic>?;
      return LeadShareEntry(
        id:                r['id'] as String,
        recipientUserId:   r['recipient_user_id'] as String,
        recipientUsername: recipientObj?['email_or_username'] as String?
            ?? r['recipient_user_id'] as String,
        grantedAt:         DateTime.parse(r['granted_at'] as String),
      );
    }).toList();
  }

  /// Active employees in caller's tenant for the share picker (Story 4.4).
  /// Caller filters out self client-side using auth.uid().
  Future<List<EmployeeRef>> listEmployeesForShare() async {
    final result = await _supabase.rpc('list_employees_for_share');
    return (result as List)
        .map((r) => EmployeeRef.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}

@riverpod
LeadRepository leadRepository(LeadRepositoryRef ref) {
  return LeadRepository(Supabase.instance.client);
}
