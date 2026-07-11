// Story 14.3-mobile — presentation helpers for inventory units.
//
// Maps UnitStatus → existing AppColors tokens (never raw hex) and formats
// paise/area for display. Four visually distinct, legend-backed states:
//   available = go (green) · hold = caution (amber) · sold = muted/taken · blocked = grey.

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/unit_model.dart';

extension UnitStatusStyle on UnitStatus {
  Color get foreground {
    switch (this) {
      case UnitStatus.available:
        return AppColors.statusSold; // green = free to sell
      case UnitStatus.hold:
        return AppColors.statusWarm; // amber = caution
      case UnitStatus.sold:
        return AppColors.inkDisabled; // muted = taken
      case UnitStatus.blocked:
        return AppColors.statusDead; // grey-blue = withheld
      case UnitStatus.unknown:
        return AppColors.inkSecondary;
    }
  }

  Color get background {
    switch (this) {
      case UnitStatus.available:
        return AppColors.statusSoldBg;
      case UnitStatus.hold:
        return AppColors.statusWarmBg;
      case UnitStatus.sold:
        return AppColors.surfaceMist; // reads as unavailable, distinct from amber hold
      case UnitStatus.blocked:
        return AppColors.statusDeadBg;
      case UnitStatus.unknown:
        return AppColors.surfaceSunk;
    }
  }

  String get label {
    switch (this) {
      case UnitStatus.available:
        return 'Available';
      case UnitStatus.hold:
        return 'On hold';
      case UnitStatus.sold:
        return 'Sold';
      case UnitStatus.blocked:
        return 'Blocked';
      case UnitStatus.unknown:
        return 'Unknown';
    }
  }
}

/// Indian lakh/crore-aware price from paise. Null → em dash.
String formatPaise(int? paise) {
  if (paise == null) return '—';
  final rupees = paise / 100;
  if (rupees >= 10000000) {
    return '₹${(rupees / 10000000).toStringAsFixed(2)} Cr';
  }
  if (rupees >= 100000) {
    return '₹${(rupees / 100000).toStringAsFixed(2)} L';
  }
  return '₹${rupees.toStringAsFixed(0)}';
}

/// Carpet area in sqft. Null → em dash.
String formatArea(num? sqft) {
  if (sqft == null) return '—';
  final s = sqft.toStringAsFixed(sqft.truncateToDouble() == sqft ? 0 : 1);
  return '$s sq.ft';
}
