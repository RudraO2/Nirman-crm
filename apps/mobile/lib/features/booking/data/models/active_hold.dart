// Story 15.5-mobile — an active hold row from get_active_holds.
//
// Mirrors the RPC's RETURNS TABLE. The live countdown uses [expiresAt] (fed to the
// reused HoldCountdown widget); [secondsToExpiry] is kept as a clockless fallback.
// Flutter-free so it stays unit-testable. Lead name is decrypted server-side (vault)
// and may be null when the key/name is absent — the UI shows a neutral "Lead" label.

class ActiveHold {
  final String holdId;
  final String unitId;
  final String unitNo;
  final String projectId;
  final String leadId;
  final String? leadName;
  final String holdingAgentId;
  final String? agentName;
  final DateTime heldAt;
  final DateTime expiresAt;
  final int secondsToExpiry;

  const ActiveHold({
    required this.holdId,
    required this.unitId,
    required this.unitNo,
    required this.projectId,
    required this.leadId,
    this.leadName,
    required this.holdingAgentId,
    this.agentName,
    required this.heldAt,
    required this.expiresAt,
    required this.secondsToExpiry,
  });

  factory ActiveHold.fromJson(Map<String, dynamic> j) => ActiveHold(
        holdId: j['hold_id'] as String,
        unitId: j['unit_id'] as String,
        unitNo: j['unit_no'] as String,
        projectId: j['project_id'] as String,
        leadId: j['lead_id'] as String,
        leadName: j['lead_name'] as String?,
        holdingAgentId: j['holding_agent_id'] as String,
        agentName: j['agent_name'] as String?,
        heldAt: DateTime.parse(j['held_at'] as String),
        expiresAt: DateTime.parse(j['expires_at'] as String),
        secondsToExpiry: (j['seconds_to_expiry'] as num?)?.toInt() ?? 0,
      );

  /// Neutral display for the agent when the username didn't resolve.
  String get agentLabel => agentName ?? 'Agent';

  /// Neutral display for the lead when the name is null (no decrypt).
  String get leadLabel =>
      (leadName != null && leadName!.isNotEmpty) ? leadName! : 'Lead';
}
