// Story 12.4-mobile — tier pill. Maps a RoleTier to an existing AppColors pair
// (never raw hex), mirroring the admin TIER_PILL palette intent.

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/hierarchy_user.dart';

class _PillStyle {
  final Color bg;
  final Color fg;
  final bool outline;
  const _PillStyle(this.bg, this.fg, {this.outline = false});
}

_PillStyle _styleFor(RoleTier tier) {
  switch (tier) {
    case RoleTier.superAdmin:
      return const _PillStyle(AppColors.evergreen, AppColors.brassBright);
    case RoleTier.builderHead:
      return const _PillStyle(AppColors.brass, Colors.white);
    case RoleTier.teamLeader:
      return const _PillStyle(AppColors.brassSoft, Color(0xFF6E5423));
    case RoleTier.frontLineRep:
      return const _PillStyle(AppColors.paper, AppColors.inkSecondary,
          outline: true);
    case RoleTier.partnerAgency:
      return const _PillStyle(AppColors.statusColdBg, AppColors.statusCold);
    case RoleTier.receptionist:
      return const _PillStyle(AppColors.mist, AppColors.inkDisabled);
    case RoleTier.unknown:
      return const _PillStyle(AppColors.mist, AppColors.inkDisabled);
  }
}

class TierPill extends StatelessWidget {
  final RoleTier tier;
  const TierPill({super.key, required this.tier});

  @override
  Widget build(BuildContext context) {
    if (tier == RoleTier.unknown) {
      return const Text('—', style: TextStyle(color: AppColors.inkDisabled));
    }
    final s = _styleFor(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(999),
        border: s.outline ? Border.all(color: AppColors.line2) : null,
      ),
      child: Text(
        tier.label,
        style: TextStyle(
          color: s.fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
