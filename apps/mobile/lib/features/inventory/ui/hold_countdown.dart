// Story 15.2-mobile — live hold countdown.
//
// Ticks once a second toward expiresAt. Amber while comfortable, red in the last
// hour, "Expired" past the deadline. The label formatter is pure + exported so it
// can be unit-tested without a running clock. Reused by Story 15.5 booking dashboard.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Pure: remaining duration → short label. Negative/zero → "Expired".
String formatRemaining(Duration remaining) {
  if (remaining <= Duration.zero) return 'Expired';
  final h = remaining.inHours;
  final m = remaining.inMinutes % 60;
  final s = remaining.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m left';
  if (m > 0) return '${m}m ${s}s left';
  return '${s}s left';
}

class HoldCountdown extends StatefulWidget {
  final DateTime expiresAt;

  /// When true, renders as a compact inline chip (grid/list). When false, a fuller
  /// row for the detail sheet.
  final bool compact;

  const HoldCountdown({super.key, required this.expiresAt, this.compact = false});

  @override
  State<HoldCountdown> createState() => _HoldCountdownState();
}

class _HoldCountdownState extends State<HoldCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.difference(DateTime.now());
    final expired = remaining <= Duration.zero;
    final urgent = !expired && remaining <= const Duration(hours: 1);
    final color = expired
        ? AppColors.inkDisabled
        : (urgent ? AppColors.statusHot : AppColors.statusWarm);
    final label = formatRemaining(remaining);

    if (widget.compact) {
      return Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          expired ? 'Hold expired' : 'Held · $label',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
