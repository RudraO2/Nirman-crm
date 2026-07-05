// Story 10.2 — Full-screen ring screen shown when a follow-up alarm fires.
//
// Reached two ways: (1) the `alarm` package's full-screen intent wakes the
// screen over the lock screen and, on tap, opens the app where the ringing
// listener (app.dart) pushes this route; (2) the app is already foregrounded.
// Shows lead name + follow-up time + offset, with Snooze (5 min) and Dismiss.
// Tapping the body dismisses and opens the lead's detail.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../data/alarm_planning.dart';
import '../data/alarm_scheduler.dart';
import '../data/models/follow_up_alarm.dart';

/// Route argument for `/alarm-ring`.
class AlarmRingArgs {
  final int alarmId;
  final FollowUpAlarmPayload payload;
  const AlarmRingArgs({required this.alarmId, required this.payload});
}

class AlarmRingScreen extends ConsumerWidget {
  final AlarmRingArgs args;
  const AlarmRingScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payload = args.payload;
    final timeStr = DateFormat('EEE d MMM, h:mm a').format(payload.followUpAt);
    final offsetLine = payload.isSnooze
        ? 'Snoozed reminder'
        : 'Rings ${humanOffsetLabel(payload.offsetMinutes)} before your follow-up';

    return PopScope(
      // The alarm is still ringing natively; force Snooze/Dismiss rather than a
      // silent system-back that would leave the alarm sounding.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.evergreen,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                const Spacer(),
                // Tap the body → open the lead.
                Expanded(
                  flex: 5,
                  child: InkWell(
                    onTap: () => _openLead(context, ref),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.alarm,
                            size: 72, color: AppColors.accentBright),
                        const SizedBox(height: 28),
                        const Text(
                          'Follow-up',
                          style: TextStyle(
                            fontSize: 15,
                            letterSpacing: 1.5,
                            color: AppColors.accentSoft,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          payload.leadName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 30,
                            height: 1.15,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 17,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          offsetLine,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: AppColors.surfaceMist,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Tap to open lead',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.surfaceMist.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _snooze(context, ref),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: AppColors.accentSoft),
                          foregroundColor: AppColors.accentSoft,
                        ),
                        child: const Text('Snooze 5 min'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _dismiss(context, ref),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: AppColors.accentStrong,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Dismiss'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _dismiss(BuildContext context, WidgetRef ref) async {
    await ref
        .read(alarmSchedulerProvider)
        .dismiss(args.alarmId, payload: args.payload);
    if (context.mounted) _close(context);
  }

  Future<void> _snooze(BuildContext context, WidgetRef ref) async {
    await ref.read(alarmSchedulerProvider).snooze(args.alarmId, args.payload);
    if (context.mounted) _close(context);
  }

  Future<void> _openLead(BuildContext context, WidgetRef ref) async {
    await ref
        .read(alarmSchedulerProvider)
        .dismiss(args.alarmId, payload: args.payload);
    if (context.mounted) context.go('/lead/${args.payload.leadId}');
  }

  void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }
}
