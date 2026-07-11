// Story 15.2-mobile — a hold on a unit.
//
// Two shapes feed this: the hold_unit RPC result ({hold_id, unit_id, status_version,
// expires_at}) and a direct tenant-scoped read of public.unit_holds (id, unit_id,
// lead_id, holding_agent_id, expires_at, ...). Both carry the one field the UI needs
// most: expiresAt (drives the countdown). Pure Dart — no Flutter.

class UnitHold {
  final String holdId;
  final String unitId;
  final DateTime expiresAt;
  final String? leadId;
  final String? holdingAgentId;
  final int? statusVersion;

  const UnitHold({
    required this.holdId,
    required this.unitId,
    required this.expiresAt,
    this.leadId,
    this.holdingAgentId,
    this.statusVersion,
  });

  /// From the hold_unit RPC jsonb result.
  factory UnitHold.fromRpc(Map<String, dynamic> json) {
    return UnitHold(
      holdId: json['hold_id'] as String,
      unitId: json['unit_id'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      statusVersion: (json['status_version'] as num?)?.toInt(),
    );
  }

  /// From a public.unit_holds table row (active-hold read).
  factory UnitHold.fromRow(Map<String, dynamic> json) {
    return UnitHold(
      holdId: json['id'] as String,
      unitId: json['unit_id'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      leadId: json['lead_id'] as String?,
      holdingAgentId: json['holding_agent_id'] as String?,
    );
  }
}
