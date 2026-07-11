// Story 16.2-mobile — execution surface renders PII-free rows + lifecycle actions,
// and shows a calm not-member state (no PII, no join button for a non-head).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nirman_crm/features/auth/data/auth_repository.dart';
import 'package:nirman_crm/features/amendments/data/amendments_repository.dart';
import 'package:nirman_crm/features/amendments/data/models/execution_amendment.dart';
import 'package:nirman_crm/features/amendments/providers/amendments_providers.dart';
import 'package:nirman_crm/features/amendments/ui/amendments_execution_screen.dart';

class _FakeAuth implements AuthRepository {
  final Session? session;
  _FakeAuth(this.session);
  @override
  Session? get currentSession => session;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ExecutionAmendment amendment() => ExecutionAmendment.fromJson({
      'amendment_id': 'am1',
      'unit_id': 'u1',
      'unit_no': '102',
      'configuration': '3BHK',
      'lead_id': 'l1',
      'description': 'East-facing balcony',
      'status': 'requested',
      'created_at': '2026-07-11T09:00:00Z',
      'updated_at': '2026-07-11T09:00:00Z',
    });

Widget host(List<Override> extra) => ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => _FakeAuth(null)),
        ...extra,
      ],
      child: const MaterialApp(home: AmendmentsExecutionScreen()),
    );

void main() {
  testWidgets('renders PII-free rows + a lifecycle action', (tester) async {
    await tester.pumpWidget(host([
      amendmentsForExecutionProvider('')
          .overrideWith((ref) async => [amendment()]),
    ]));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unit 102'), findsOneWidget);
    expect(find.text('East-facing balcony'), findsOneWidget);
    // 'Requested' shows twice: the status filter chip + the row's status pill.
    expect(find.text('Requested'), findsNWidgets(2));
    // From 'requested' the allowed actions are Acknowledged / Reject.
    // 'Acknowledged' also appears as a filter chip → chip + action = 2.
    expect(find.text('Acknowledged'), findsNWidgets(2));
    // 'Reject' is only the action (the filter chip reads 'Rejected').
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('not-member shows a calm state, no join button for non-head',
      (tester) async {
    await tester.pumpWidget(host([
      amendmentsForExecutionProvider('').overrideWith(
        (ref) async => throw const ExecutionException('not_execution_member',
            notMember: true),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text("You're not on the execution team."), findsOneWidget);
    expect(find.text('Join execution team'), findsNothing);
  });
}
