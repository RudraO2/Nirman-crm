// Story 2.5 — LeadCard widget smoke tests.
// Verifies rendering: name, status pill, incomplete indicator, pending-outcome accent.
// Run with: flutter test test/features/leads/lead_card_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/leads/data/models/lead_model.dart';
import 'package:nirman_crm/features/leads/ui/lead_card.dart';

LeadListItem _lead({
  String id = 'x',
  String status = 'hot',
  String? name = 'Anita Sharma',
  String? phone = '9876543210',
  String? location,
  bool isIncomplete = false,
  DateTime? pendingOutcomeAt,
  DateTime? nextFollowupAt,
  DateTime? lastActionAt,
}) =>
    LeadListItem(
      id: id,
      status: status,
      name: name,
      phone: phone,
      location: location,
      isIncomplete: isIncomplete,
      pendingOutcomeAt: pendingOutcomeAt,
      nextFollowupAt: nextFollowupAt,
      lastActionAt: lastActionAt,
      createdAt: DateTime(2026, 5, 20),
      urgencyScore: 100,
    );

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('LeadCard — basic rendering', () {
    testWidgets('shows lead name', (tester) async {
      await tester.pumpWidget(_wrap(LeadCard(lead: _lead())));
      expect(find.text('Anita Sharma'), findsOneWidget);
    });

    testWidgets('shows formatted phone', (tester) async {
      await tester.pumpWidget(_wrap(LeadCard(lead: _lead())));
      expect(find.text('98765 43210'), findsOneWidget);
    });

    testWidgets('shows status pill text', (tester) async {
      await tester.pumpWidget(_wrap(LeadCard(lead: _lead(status: 'hot'))));
      expect(find.text('Hot'), findsOneWidget);
    });

    testWidgets('shows location when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        LeadCard(lead: _lead(location: 'Bandra')),
      ));
      expect(find.text('Bandra'), findsOneWidget);
    });

    testWidgets('shows "No name" when name is null', (tester) async {
      await tester.pumpWidget(_wrap(LeadCard(lead: _lead(name: null))));
      expect(find.text('No name'), findsOneWidget);
    });
  });

  group('LeadCard — incomplete indicator', () {
    testWidgets('shows Incomplete text when isIncomplete=true', (tester) async {
      await tester.pumpWidget(_wrap(LeadCard(lead: _lead(isIncomplete: true))));
      expect(find.text('Incomplete'), findsOneWidget);
    });

    testWidgets('no Incomplete text when isIncomplete=false', (tester) async {
      await tester.pumpWidget(_wrap(LeadCard(lead: _lead(isIncomplete: false))));
      expect(find.text('Incomplete'), findsNothing);
    });
  });

  group('LeadCard — pending outcome badge', () {
    testWidgets('shows Awaiting outcome when pendingOutcomeAt is set', (tester) async {
      await tester.pumpWidget(_wrap(LeadCard(
        lead: _lead(pendingOutcomeAt: DateTime.now()),
      )));
      expect(find.text('Awaiting outcome'), findsOneWidget);
    });

    testWidgets('no Awaiting outcome badge when pendingOutcomeAt is null', (tester) async {
      await tester.pumpWidget(_wrap(LeadCard(lead: _lead())));
      expect(find.text('Awaiting outcome'), findsNothing);
    });
  });

  group('LeadCard — follow-up label', () {
    testWidgets('shows overdue label when nextFollowupAt is past', (tester) async {
      await tester.pumpWidget(_wrap(LeadCard(
        lead: _lead(
          nextFollowupAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      )));
      expect(find.textContaining('Overdue'), findsOneWidget);
    });

    testWidgets('shows Today label when nextFollowupAt is today', (tester) async {
      final now = DateTime.now();
      final todayNoon = DateTime(now.year, now.month, now.day, 12, 0);
      await tester.pumpWidget(_wrap(LeadCard(
        lead: _lead(nextFollowupAt: todayNoon),
      )));
      expect(find.textContaining('Today'), findsOneWidget);
    });
  });

  group('LeadCard — status pill variants', () {
    for (final statusLabel in [
      ('warm', 'Warm'),
      ('cold', 'Cold'),
      ('future', 'Future'),
      ('sold', 'Sold'),
      ('dead', 'Dead'),
    ]) {
      testWidgets('shows ${statusLabel.$2} pill for ${statusLabel.$1}', (tester) async {
        await tester.pumpWidget(_wrap(
          LeadCard(lead: _lead(status: statusLabel.$1)),
        ));
        expect(find.text(statusLabel.$2), findsOneWidget);
      });
    }
  });

  group('LeadCard — tap callback', () {
    testWidgets('fires onTap when card is tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        LeadCard(lead: _lead(), onTap: () => tapped = true),
      ));
      await tester.tap(find.byType(LeadCard));
      expect(tapped, true);
    });
  });
}
