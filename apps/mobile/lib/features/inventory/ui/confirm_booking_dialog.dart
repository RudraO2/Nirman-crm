// Story 15.4-mobile — payment-verified attestation before confirming a booking.
//
// A deliberate two-step (AC2): the "Confirm — mark Sold" button stays disabled until
// the manager ticks "Payment is verified". Returns true only if they attest + confirm.

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

Future<bool> showConfirmBookingDialog(BuildContext context, String unitNo) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => const _ConfirmBookingDialog(),
  );
  return result ?? false;
}

class _ConfirmBookingDialog extends StatefulWidget {
  const _ConfirmBookingDialog();

  @override
  State<_ConfirmBookingDialog> createState() => _ConfirmBookingDialogState();
}

class _ConfirmBookingDialogState extends State<_ConfirmBookingDialog> {
  bool _verified = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceRaised,
      title: const Text('Confirm booking'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This marks the unit and the lead as Sold. It cannot be undone without a '
            'Builder Head override.',
            style: TextStyle(fontSize: 13, color: AppColors.inkSecondary),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _verified,
            onChanged: (v) => setState(() => _verified = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.evergreen,
            title: const Text('Payment is verified',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _verified ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.statusSold,
            disabledBackgroundColor: AppColors.surfaceMist,
          ),
          child: const Text('Confirm — mark Sold'),
        ),
      ],
    );
  }
}
