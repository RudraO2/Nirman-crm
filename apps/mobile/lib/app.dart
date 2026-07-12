import 'dart:async';

import 'package:alarm/alarm.dart' as alarm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/notifications_service.dart';
import 'core/theme/app_theme.dart';
import 'features/alarms/data/models/follow_up_alarm.dart';
import 'features/alarms/ui/alarm_ring_screen.dart';
import 'features/billing/providers/billing_providers.dart';
import 'router/app_router.dart';

class NirmanApp extends ConsumerStatefulWidget {
  const NirmanApp({super.key});

  @override
  ConsumerState<NirmanApp> createState() => _NirmanAppState();
}

class _NirmanAppState extends ConsumerState<NirmanApp> {
  StreamSubscription<dynamic>? _ringingSub;

  /// Alarm ids for which the ring screen is already shown — prevents duplicate
  /// pushes while an alarm keeps emitting on the ringing stream.
  final Set<int> _shown = {};

  StreamSubscription<dynamic>? _authSub;

  @override
  void initState() {
    super.initState();
    // Notification permission is asked HERE — on sign-in / restored session —
    // not at cold start on the login screen (contextless asks get denied).
    // enablePush() no-ops when Firebase is down or already enabled.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session != null) NotificationsService.enablePush();
    });
    // Story 10.2 — when a follow-up alarm rings (incl. cold-start from the
    // full-screen intent), open the ring screen for each newly ringing alarm.
    _ringingSub = alarm.Alarm.ringing.listen((alarmSet) {
      final ringingIds = alarmSet.alarms.map((a) => a.id).toSet();
      _shown.removeWhere((id) => !ringingIds.contains(id));
      for (final a in alarmSet.alarms) {
        if (!_shown.add(a.id)) continue; // already showing
        final payload = FollowUpAlarmPayload.tryDecode(a.payload);
        if (payload == null) continue; // not a follow-up alarm — ring natively
        appRouter.push(
          '/alarm-ring',
          extra: AlarmRingArgs(alarmId: a.id, payload: payload),
        );
      }
    });
  }

  @override
  void dispose() {
    _ringingSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Story 9.6 — keep the billing gate alive app-wide and mirror its locked-out
    // state into the router's notifier, so the redirect covers EVERY route (not
    // just the tab shell). `listen` keeps the provider subscribed without rebuilding
    // the whole MaterialApp on each billing change.
    ref.listen(billingGateProvider, (_, next) {
      next.whenData((g) => billingLockNotifier.value = g.isLockedOut);
    });

    return MaterialApp.router(
      title: 'Nirman CRM',
      theme: _buildTheme(),
      routerConfig: appRouter,
    );
  }
}

ThemeData _buildTheme() {
  final base = ThemeData(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.surfaceBase,
    colorScheme: const ColorScheme.light(
      primary:    AppColors.accentStrong,
      secondary:  AppColors.accent,
      surface:    AppColors.surfaceBase,
      onPrimary:  AppColors.surfaceBase,
      onSecondary: AppColors.surfaceBase,
      onSurface:  AppColors.inkPrimary,
      error:      AppColors.error,
    ),
    // Inter for body/base text; Fraunces (display serif) applied per-heading.
    textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
      bodyMedium: GoogleFonts.inter(
        fontSize: 16,
        color: AppColors.inkPrimary,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 14,
        color: AppColors.inkSecondary,
      ),
    ),
    // Eyeball feedback A2 — the old navy/ivory default made the back arrow
    // ivory-on-ivory on every screen that overrode the bar background to
    // surfaceBase without also overriding iconTheme (Team leads, Availability,
    // …). Every real screen uses this palette, so it IS the default now; no
    // screen can forget the icon color again.
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surfaceBase,
      foregroundColor: AppColors.inkPrimary,
      iconTheme: const IconThemeData(color: AppColors.inkPrimary),
      // ui-modern-refresh: one family — titles are Inter w800 tight, not a
      // display serif. Screens that pass their own style get the same look
      // via AppType.display.
      titleTextStyle: AppType.display(fontSize: 21),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    // ui-modern-refresh: one button vocabulary app-wide (DESIGN.md §Components).
    // Primary = evergreen block, brass-bright label, h52, radius 13, no shadow.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.evergreen,
        foregroundColor: AppColors.brassBright,
        disabledBackgroundColor: AppColors.surfaceMist,
        disabledForegroundColor: AppColors.inkDisabled,
        elevation: 0,
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.inkPrimary,
        side: const BorderSide(color: AppColors.borderStrong, width: 1.2),
        minimumSize: const Size(64, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentStrong,
        textStyle: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    // Eyeball feedback A3 — the mark-dead snackbar was WHITE (surfaceRaised)
    // with Material's default light content text: white-on-white, and its
    // Undo action barely read. One coherent theme-level spec — dark evergreen
    // bar, ivory text, brass-bright action — so every snackbar is legible and
    // no call site needs (or should set) its own colors.
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.evergreen,
      contentTextStyle: TextStyle(color: Color(0xFFF2EEE2), fontSize: 14),
      actionTextColor: AppColors.accentBright,
      behavior: SnackBarBehavior.floating,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accentStrong,
      foregroundColor: AppColors.surfaceBase,
      elevation: 3,
    ),
    dividerColor: AppColors.borderHairline,
  );
}
