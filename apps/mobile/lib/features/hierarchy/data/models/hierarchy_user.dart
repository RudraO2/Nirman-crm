// Story 12.4-mobile — hierarchy user + role-tier model.
//
// Mirrors the `users` select used by the admin /hierarchy page (page.tsx) and the
// set_user_hierarchy RPC contract (migration 0059). Pure Dart — no Flutter/theme
// imports so it stays unit-testable; the tier-pill colours live in ui/tier_pill.dart.

/// The six role tiers (public.role_tier enum, migration 0057). `unknown` is a
/// defensive fallback if the backend ever returns a value this client build
/// doesn't know — it is treated as off-ladder (rank 0, no reports_to).
enum RoleTier {
  superAdmin('super_admin', 'Super Admin', 4, true),
  builderHead('builder_head', 'Builder Head', 3, true),
  teamLeader('team_leader', 'Team Leader', 2, true),
  frontLineRep('front_line_rep', 'Front-line Rep', 1, true),
  partnerAgency('partner_agency', 'Partner · Agency', 0, false),
  receptionist('receptionist', 'Reception', 0, false),
  unknown('', '—', 0, false);

  const RoleTier(this.dbValue, this.label, this.rank, this.isLadder);

  /// The exact `public.role_tier` enum string. Sent to the RPC as `p_role_tier`.
  final String dbValue;

  /// Human label for pills / dropdowns.
  final String label;

  /// Ordinal for "strictly higher tier" checks — mirrors `role_tier_rank`
  /// (super=4 > head=3 > leader=2 > rep=1; off-ladder=0). [Source: 0059]
  final int rank;

  /// True for the internal sales ladder (super/head/leader/rep). Off-ladder tiers
  /// (partner/receptionist) never carry a reports_to.
  final bool isLadder;

  static RoleTier fromDb(String? value) {
    for (final t in RoleTier.values) {
      if (t != RoleTier.unknown && t.dbValue == value) return t;
    }
    return RoleTier.unknown;
  }

  /// Tiers offered in the edit dropdown (excludes the defensive `unknown`).
  static List<RoleTier> get selectable =>
      RoleTier.values.where((t) => t != RoleTier.unknown).toList();
}

/// One row from the `users` table (active members of the caller's tenant).
class HierarchyUser {
  final String id;
  final String emailOrUsername;
  final String role;
  final RoleTier roleTier;
  final String? reportsToUserId;
  final String? agencyId;
  final bool isExternal;
  final bool isActive;

  const HierarchyUser({
    required this.id,
    required this.emailOrUsername,
    required this.role,
    required this.roleTier,
    required this.reportsToUserId,
    required this.agencyId,
    required this.isExternal,
    required this.isActive,
  });

  factory HierarchyUser.fromJson(Map<String, dynamic> json) {
    return HierarchyUser(
      id: json['id'] as String,
      emailOrUsername: json['email_or_username'] as String,
      role: (json['role'] as String?) ?? '',
      roleTier: RoleTier.fromDb(json['role_tier'] as String?),
      reportsToUserId: json['reports_to_user_id'] as String?,
      agencyId: json['agency_id'] as String?,
      isExternal: (json['is_external'] as bool?) ?? false,
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

/// Pure logic: valid managers for a user being set to [tier] — internal ladder
/// users of strictly-higher rank, excluding the user themselves. Mirrors the
/// admin `managerOptions` filter (hierarchy-client.tsx) so the picker never offers
/// an invalid parent (the RPC would reject it anyway). Off-ladder tiers get [].
List<HierarchyUser> managerOptionsFor({
  required RoleTier tier,
  required String editingUserId,
  required List<HierarchyUser> allUsers,
}) {
  if (!tier.isLadder) return const [];
  return allUsers
      .where((u) =>
          u.id != editingUserId &&
          u.roleTier.isLadder &&
          u.roleTier.rank > tier.rank)
      .toList();
}
