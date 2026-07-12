// Eyeball feedback A1 — the Material clock dial (tap hours on a dial, then
// minutes, 24h labels) fails the 45-year-old-rep test. This is the pattern
// every phone's alarm app uses instead: scroll wheels, 12-hour + AM/PM,
// 5-minute steps (follow-ups don't need :07 precision).
//
// Drop-in replacement for showTimePicker — returns TimeOfDay? the same way,
// so call sites swap one function name.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

Future<TimeOfDay?> showWheelTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  // Align to the 5-minute wheel step (round down; 11:58 → 11:55).
  final aligned = initialTime.replacing(
    minute: initialTime.minute - (initialTime.minute % 5),
  );
  var selected = DateTime(2000, 1, 1, aligned.hour, aligned.minute);

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Pick a time', style: AppType.display(fontSize: 20)),
            const SizedBox(height: 8),
            SizedBox(
              height: 190,
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkPrimary,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: false,
                  minuteInterval: 5,
                  initialDateTime: selected,
                  onDateTimeChanged: (dt) => selected = dt,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.of(sheetCtx).pop(
                TimeOfDay(hour: selected.hour, minute: selected.minute),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ),
  );
}
