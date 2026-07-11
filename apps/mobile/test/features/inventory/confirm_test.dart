// Story 15.4-mobile — ConfirmException mapping + payment-attestation dialog gating.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nirman_crm/features/inventory/data/inventory_repository.dart';
import 'package:nirman_crm/features/inventory/ui/confirm_booking_dialog.dart';

void main() {
  group('ConfirmException.fromPostgrest', () {
    ConfirmException map(String message) =>
        ConfirmException.fromPostgrest(PostgrestException(message: message));

    test('forbidden_role → notAllowed', () {
      final e = map('forbidden_role: only builder_head or team_leader may confirm');
      expect(e.notAllowed, isTrue);
      expect(e.stale, isFalse);
    });
    test('payment_not_verified → paymentNotVerified', () {
      final e = map('payment_not_verified: confirmation requires verified payment');
      expect(e.paymentNotVerified, isTrue);
    });
    test('hold_not_active → stale', () {
      expect(map('hold_not_active: hold already released/expired/converted').stale, isTrue);
    });
    test('unit_not_held → stale', () {
      expect(map('unit_not_held: unit is not in hold state').stale, isTrue);
    });
    test('unknown → generic', () {
      final e = map('some_other_error');
      expect(e.notAllowed, isFalse);
      expect(e.stale, isFalse);
      expect(e.paymentNotVerified, isFalse);
    });
  });

  group('payment attestation dialog', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showConfirmBookingDialog(ctx, 'A-301'),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    FilledButton confirmButton(WidgetTester tester) => tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Confirm — mark Sold'),
            matching: find.byType(FilledButton),
          ),
        );

    testWidgets('Confirm disabled until "Payment is verified" ticked',
        (tester) async {
      await open(tester);
      expect(confirmButton(tester).onPressed, isNull);

      await tester.tap(find.text('Payment is verified'));
      await tester.pumpAndSettle();
      expect(confirmButton(tester).onPressed, isNotNull);
    });

    testWidgets('Cancel returns without enabling', (tester) async {
      await open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm — mark Sold'), findsNothing);
    });
  });
}
