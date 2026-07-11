// Story 14.3-mobile — inventory unit model.
//
// Mirrors the get_project_units(p_project_id) RETURNS TABLE contract
// (migration 0072_project_units_read.sql). Pure Dart — no Flutter imports so it
// stays unit-testable and free of the theme layer (colours live in ui/unit_status_style.dart).

/// The unit status state machine (Epic 14 / arch §13.3). `unknown` is a defensive
/// fallback if the backend ever returns a value this client build doesn't know.
enum UnitStatus {
  available,
  hold,
  sold,
  blocked,
  unknown;

  static UnitStatus fromDb(String? value) {
    switch (value) {
      case 'available':
        return UnitStatus.available;
      case 'hold':
        return UnitStatus.hold;
      case 'sold':
        return UnitStatus.sold;
      case 'blocked':
        return UnitStatus.blocked;
      default:
        return UnitStatus.unknown;
    }
  }
}

/// One unit row from `get_project_units`.
///
/// [costPaise] (margin) is returned NON-null ONLY to builder_head; for every
/// other tier the RPC sends NULL. The UI must treat null as "hide margin" — never
/// as ₹0.
class ProjectUnit {
  final String unitId;
  final String? towerId;
  final String? towerName;
  final String unitNo;
  final int? floor;
  final String? configuration;
  final num? carpetAreaSqft;
  final UnitStatus status;
  final int? listPricePaise;
  final int? costPaise;
  final int statusVersion;

  const ProjectUnit({
    required this.unitId,
    required this.towerId,
    required this.towerName,
    required this.unitNo,
    required this.floor,
    required this.configuration,
    required this.carpetAreaSqft,
    required this.status,
    required this.listPricePaise,
    required this.costPaise,
    required this.statusVersion,
  });

  /// True only when the RPC returned a margin (i.e. the caller is builder_head).
  bool get hasMargin => costPaise != null;

  factory ProjectUnit.fromJson(Map<String, dynamic> json) {
    return ProjectUnit(
      unitId: json['unit_id'] as String,
      towerId: json['tower_id'] as String?,
      towerName: json['tower_name'] as String?,
      unitNo: json['unit_no'] as String,
      floor: (json['floor'] as num?)?.toInt(),
      configuration: json['configuration'] as String?,
      carpetAreaSqft: json['carpet_area_sqft'] as num?,
      status: UnitStatus.fromDb(json['status'] as String?),
      listPricePaise: (json['list_price_paise'] as num?)?.toInt(),
      costPaise: (json['cost_paise'] as num?)?.toInt(),
      statusVersion: (json['status_version'] as num?)?.toInt() ?? 0,
    );
  }
}
