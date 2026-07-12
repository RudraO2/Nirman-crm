import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Brand palette — UI redesign tokens (see ui-redesign/redesign-handoff.md §3).
// Constant NAMES are preserved so existing call sites restyle "for free"; only
// the values changed. New evergreen / status-bg / brass tokens are added for the
// redesigned surfaces (dark header card, status pills, sheets).
// Do NOT use Material ColorScheme seeds — always reference these named constants.

class AppColors {
  // Surfaces
  static const surfaceBase   = Color(0xFFF6F3EC); // ivory — primary background
  static const surfaceRaised = Color(0xFFFFFFFF); // paper — cards, panels
  static const surfaceSunk   = Color(0xFFEDE8DD); // mist — input fills, sunk
  static const surfaceMist   = Color(0xFFCFC8B8); // line-2 — disabled fills

  // Ink
  static const inkPrimary    = Color(0xFF1C231F); // body text, headings
  static const inkSecondary  = Color(0xFF5C665F); // metadata, captions
  static const inkDisabled   = Color(0xFF98A29A); // disabled / faint text

  // Structure
  static const borderHairline = Color(0xFFE4DFD3); // line — hairline borders
  static const borderStrong   = Color(0xFFCFC8B8); // line-2 — input borders

  // Navy → cold blue (§3: navy → #3E6DA6)
  static const navy      = Color(0xFF3E6DA6);
  static const navySoft  = Color(0xFF5C86BC);
  static const navyDeep  = Color(0xFF2C4E78);

  // Accent — brass (the moment marker)
  static const accent        = Color(0xFFC9A354); // brass-bright — soft CTAs
  static const accentStrong  = Color(0xFFA8823C); // brass — primary CTAs, accent
  static const accentSoft    = Color(0xFFEADFC4); // brass-soft — soft fills
  static const accentBright  = Color(0xFFC9A354); // brass-bright — on dark, Sold

  // Status — foreground colors (§3)
  static const statusHot        = Color(0xFFC24638);
  static const statusWarm       = Color(0xFFC07A17);
  static const statusCold       = Color(0xFF3E6DA6);
  static const statusFuture     = Color(0xFF7A5BA8);
  static const statusSold       = Color(0xFF2F7D4F);
  static const statusDead       = Color(0xFF78817B);
  static const statusStale      = Color(0xFF78817B);
  static const statusIncomplete = Color(0xFFC24638);

  // Status — tinted pill backgrounds (§3)
  static const statusHotBg    = Color(0xFFF9E9E6);
  static const statusWarmBg   = Color(0xFFF7EDD9);
  static const statusColdBg   = Color(0xFFE6EDF6);
  static const statusFutureBg = Color(0xFFEEE8F6);
  static const statusSoldBg   = Color(0xFFE3F0E7);
  static const statusDeadBg   = Color(0xFFECEEEC);

  // Evergreen — dark hero / header surfaces, FAB, primary dark buttons
  static const evergreen      = Color(0xFF132A21);
  static const evergreenLight = Color(0xFF1B382C); // hover / raised on dark
  static const evergreenDeep  = Color(0xFF0D1F18); // gradient end

  // Named brand tokens (aliases for the raw palette, for redesign surfaces)
  static const ivory       = Color(0xFFF6F3EC);
  static const paper       = Color(0xFFFFFFFF);
  static const mist        = Color(0xFFEDE8DD);
  static const brass       = Color(0xFFA8823C);
  static const brassSoft   = Color(0xFFEADFC4);
  static const brassBright = Color(0xFFC9A354);
  static const line        = Color(0xFFE4DFD3);
  static const line2       = Color(0xFFCFC8B8);

  // Functional
  static const error        = Color(0xFFB3372B); // danger
  static const errorFill    = Color(0xFFC24638);
  static const success      = Color(0xFF2F7D4F);
  static const danger       = Color(0xFFB3372B);
  static const waGreen      = Color(0xFF25D366); // WhatsApp / call green
  static const pendingOutcome = Color(0xFFEADFC4); // brass-soft
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

  /// Tinted background for a status pill (pairs with [statusColor]).
  Color get statusBgColor {
    switch (this) {
      case 'hot':    return AppColors.statusHotBg;
      case 'warm':   return AppColors.statusWarmBg;
      case 'cold':   return AppColors.statusColdBg;
      case 'future': return AppColors.statusFutureBg;
      case 'sold':   return AppColors.statusSoldBg;
      case 'dead':   return AppColors.statusDeadBg;
      default:       return AppColors.statusColdBg;
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

/// ui-modern-refresh (2026-07-12, DESIGN.md §Typography) — ONE type family.
///
/// Every screen/sheet title in the app calls [AppType.display]. It used to be
/// GoogleFonts.fraunces (display serif) which clashed with the Inter body
/// ("font difference on top") and read dated. Now the same family as body,
/// carried by weight + tight tracking instead of a second font.
///
/// The incoming [fontWeight] from old call sites is deliberately IGNORED:
/// serif title weights (w500/w600) are too light for a sans title. Optical
/// rule instead: <24px → w800, >=24px → w700. Swap this ONE function to
/// re-skin every title in the app.
class AppType {
  AppType._();

  static TextStyle display({
    double fontSize = 21,
    FontWeight? fontWeight, // accepted + ignored — see doc comment
    Color color = AppColors.inkPrimary,
    double? height,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontSize >= 24 ? FontWeight.w700 : FontWeight.w800,
      letterSpacing: -0.4,
      color: color,
      height: height,
    );
  }
}
