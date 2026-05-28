import 'package:flutter/material.dart';

// Brand palette — sourced from DESIGN.md (nirmanmedia.com)
// Use these constants wherever brand colors are needed. Do NOT use Material
// ColorScheme seeds — always reference these named constants directly.

class AppColors {
  // Surfaces
  static const surfaceBase   = Color(0xFFF2EBDB); // cream — primary background
  static const surfaceRaised = Color(0xFFECE3CD); // cards, panels
  static const surfaceSunk   = Color(0xFFE8DEC4); // input fills
  static const surfaceMist   = Color(0xFFD9CDB1); // disabled fills

  // Ink
  static const inkPrimary    = Color(0xFF2A2620); // body text, headings
  static const inkSecondary  = Color(0xFF4A443B); // metadata, captions
  static const inkDisabled   = Color(0xFF928670); // disabled text

  // Structure
  static const borderHairline = Color(0xFFC0B395);
  static const borderStrong   = Color(0xFF928670);

  // Navy
  static const navy      = Color(0xFF1F2A3D);
  static const navySoft  = Color(0xFF2F3A4F);
  static const navyDeep  = Color(0xFF1A2638);

  // Gold (the moment marker)
  static const accent        = Color(0xFFC19A4A); // primary CTAs, Warm status
  static const accentStrong  = Color(0xFF8B6520); // Hot status, urgent
  static const accentSoft    = Color(0xFFDCC58D); // Pending Outcome, soft
  static const accentBright  = Color(0xFFD4AE5C); // Sold celebration

  // Status
  static const statusHot      = Color(0xFF8B6520);
  static const statusWarm     = Color(0xFFC19A4A);
  static const statusCold     = Color(0xFF928670);
  static const statusFuture   = Color(0xFF2F3A4F);
  static const statusSold     = Color(0xFFD4AE5C);
  static const statusDead     = Color(0xFF928670);
  static const statusStale    = Color(0xFF928670);
  static const statusIncomplete = Color(0xFFB8513A);

  // Functional
  static const error        = Color(0xFF9C3D2A);
  static const errorFill    = Color(0xFFB8513A);
  static const success      = Color(0xFF4A6A3F);
  static const pendingOutcome = Color(0xFFDCC58D);
}

// Status display helpers
extension LeadStatusDisplay on String {
  Color get statusColor {
    switch (this) {
      case 'hot':    return AppColors.statusHot;
      case 'warm':   return AppColors.statusWarm;
      case 'cold':   return AppColors.statusCold;
      case 'future': return AppColors.statusFuture;
      case 'sold':   return AppColors.statusSold;
      case 'dead':   return AppColors.statusDead;
      default:       return AppColors.statusCold;
    }
  }

  String get statusLabel {
    switch (this) {
      case 'hot':    return 'Hot';
      case 'warm':   return 'Warm';
      case 'cold':   return 'Cold';
      case 'future': return 'Future';
      case 'sold':   return 'Sold';
      case 'dead':   return 'Dead';
      default:       return 'Unknown';
    }
  }
}
