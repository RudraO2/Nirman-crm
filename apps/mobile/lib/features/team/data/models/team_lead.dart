// Story 12.6-mobile — team-scoped lead + owner.
//
// Reuses LeadListItem (leads feature) for the lead body — get_team_leads returns a
// superset of get_my_leads' columns — and adds the owner id the RPC surfaces so a
// leader/head/partner can see who holds each lead. Pure Dart.

import '../../../leads/data/models/lead_model.dart';

class TeamLead {
  final LeadListItem lead;

  /// `assigned_to_user_id` from get_team_leads — the lead's owner (may be the
  /// caller themselves). Null only if the RPC ever omits it (defensive).
  final String? ownerId;

  const TeamLead({required this.lead, required this.ownerId});

  String get id => lead.id;

  factory TeamLead.fromJson(Map<String, dynamic> j) {
    return TeamLead(
      lead: LeadListItem.fromJson(j),
      ownerId: j['assigned_to_user_id'] as String?,
    );
  }
}

/// Pure: the distinct, non-null owner ids in [leads]. Drives the BOUNDED owner-name
/// lookup — we only ever resolve names for owners that actually appear in the
/// returned leads, never the whole tenant roster (keeps the partner sandbox intact).
Set<String> distinctOwnerIds(List<TeamLead> leads) {
  final ids = <String>{};
  for (final t in leads) {
    final id = t.ownerId;
    if (id != null && id.isNotEmpty) ids.add(id);
  }
  return ids;
}

/// Display label for an owner: the resolved name, else a stable masked fallback
/// ("Teammate ·1a2b") so an unresolved id still reads sensibly without leaking a
/// raw uuid. Null owner → "Unassigned".
String ownerLabel(String? ownerId, Map<String, String> names) {
  if (ownerId == null || ownerId.isEmpty) return 'Unassigned';
  final name = names[ownerId];
  if (name != null && name.isNotEmpty) return name;
  final tail = ownerId.length >= 4 ? ownerId.substring(0, 4) : ownerId;
  return 'Teammate ·$tail';
}
