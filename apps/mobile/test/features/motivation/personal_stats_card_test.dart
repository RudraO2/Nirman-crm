// Story 7.1 — PersonalStatsCard widget tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nirman_crm/features/motivation/data/models/motivation_stats.dart';
import 'package:nirman_crm/features/motivation/providers/motivation_providers.dart';
import 'package:nirman_crm/features/motivation/ui/personal_stats_card.dart';

Widget _wrap(MotivationStats stats) {
  return ProviderScope(
    overrides: [
      myMotivationStatsProvider.overrideWith((ref) async => stats),
    ],
    child: const MaterialApp(
      home: Scaffold(body: PersonalStatsCard()),
    ),
  );
}

void main() {
  testWidgets('renders the three labelled stat values', (tester) async {
    await tester.pumpWidget(_wrap(MotivationStats(
      soldThisMonth: 3,
      followupStreakDays: 5,
      conversionRate: 12.5,
      totalAssigned: 24,
      fetchedAt: DateTime.now(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('MY PROGRESS'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Sold this month'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Day streak'), findsOneWidget);
    expect(find.text('12.5%'), findsOneWidget);
    expect(find.text('Conversion'), findsOneWidget);
  });

  testWidgets('fresh fetch shows no "Updated" subtitle', (tester) async {
    await tester.pumpWidget(_wrap(MotivationStats(
      soldThisMonth: 1,
      followupStreakDays: 2,
      conversionRate: 4.0,
      totalAssigned: 25,
      fetchedAt: DateTime.now(),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Updated'), findsNothing);
  });

  testWidgets('cached snapshot shows "Updated …" subtitle', (tester) async {
    await tester.pumpWidget(_wrap(MotivationStats(
      soldThisMonth: 1,
      followupStreakDays: 2,
      conversionRate: 4.0,
      totalAssigned: 25,
      fetchedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Updated'), findsOneWidget);
  });
}
