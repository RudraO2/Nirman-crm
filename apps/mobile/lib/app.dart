import 'dart:async';

import 'package:alarm/alarm.dart' as alarm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/theme/app_theme.dart';
import 'features/alarms/data/models/follow_up_alarm.dart';
import 'features/alarms/ui/alarm_ring_screen.dart';
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

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: AppColors.surfaceBase,
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accentStrong,
      foregroundColor: AppColors.surfaceBase,
      elevation: 3,
    ),
    dividerColor: AppColors.borderHairline,
  );
}
