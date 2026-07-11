// Story 13.4-mobile — reception screen: success shows ordinal + clears input;
// a rejected code keeps the input and shows the friendly message (no red dump).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/reception/data/models/visit_result.dart';
import 'package:nirman_crm/features/reception/data/reception_repository.dart';
import 'package:nirman_crm/features/reception/ui/verify_visit_screen.dart';

class _FakeRepo implements ReceptionRepository {
  final VisitResult? result;
  final Object? error;
  String? lastCode;
  _FakeRepo({this.result, this.error});

  @override
  Future<VisitResult> verifyVisit(String code) async {
    lastCode = code;
    if (error != null) throw error!;
    return result!;
  }
}

Widget host(_FakeRepo repo) => ProviderScope(
      overrides: [
        receptionRepositoryProvider.overrideWith((ref) => repo),
      ],
      child: const MaterialApp(home: VerifyVisitScreen()),
    );

void main() {
  testWidgets('valid code → shows ordinal + clears input', (tester) async {
    final repo = _FakeRepo(result: const VisitResult(leadId: 'l1', visitCount: 2));
    await tester.pumpWidget(host(repo));

    await tester.enterText(find.byType(TextField), 'nir-44d77');
    await tester.pump(); // let onChanged setState enable the button
    await tester.tap(find.text('Verify visit'));
    await tester.pumpAndSettle();

    // Normalised to uppercase before the RPC call.
    expect(repo.lastCode, 'NIR-44D77');
    expect(find.text('Visit recorded'), findsOneWidget);
    expect(find.textContaining('2nd visit'), findsOneWidget);
    // Field cleared for the next walk-in.
    expect(
      (tester.widget<TextField>(find.byType(TextField))).controller!.text,
      isEmpty,
    );
  });

  testWidgets('rejected code → friendly message, input retained', (tester) async {
    final repo = _FakeRepo(
      error: const VerifyVisitException('invalid_customer_code', notFound: true),
    );
    await tester.pumpWidget(host(repo));

    await tester.enterText(find.byType(TextField), 'BADCODE');
    await tester.pump(); // let onChanged setState enable the button
    await tester.tap(find.text('Verify visit'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No lead matches'), findsOneWidget);
    expect(find.text('Visit recorded'), findsNothing);
    // Input kept so the receptionist can correct it.
    expect(
      (tester.widget<TextField>(find.byType(TextField))).controller!.text,
      'BADCODE',
    );
  });
}
