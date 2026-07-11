// Story 15.5-mobile — dashboard renders stats tiles + active holds (with a live
// countdown) and a calm empty state, plus the agent filter (roster derived from the
// holds; list filtered client-side, stats re-fetched per agent). Providers are
// overridden with fakes; we pump single frames (HoldCountdown runs a 1 Hz Timer, so
// pumpAndSettle would hang).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/booking/data/models/active_hold.dart';
import 'package:nirman_crm/features/booking/data/models/booking_stats.dart';
import 'package:nirman_crm/features/booking/providers/booking_providers.dart';
import 'package:nirman_crm/features/booking/ui/booking_dashboard_screen.dart';
import 'package:nirman_crm/features/leads/data/models/lead_model.dart';
import 'package:nirman_crm/features/leads/providers/lead_providers.dart';

ActiveHold hold({
  String holdId = 'h1',
  String unitNo = '102',
  String leadName = 'Asha',
  String agentId = 'a1',
  String agentName = 'rep1@x',
}) =>
    ActiveHold.fromJson({
      'hold_id': holdId,
      'unit_id': 'u_$holdId',
      'unit_no': unitNo,
      'project_id': 'p1',
      'lead_id': 'l_$holdId',
      'lead_name': leadName,
      'holding_agent_id': agentId,
      'agent_name': agentName,
      'held_at': DateTime.now().toUtc().toIso8601String(),
      'expires_at':
          DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String(),
      'seconds_to_expiry': 18000,
    });

Widget host({
  required List<ActiveHold> holds,
  required BookingStats stats,
  List<Override> extra = const [],
}) =>
    ProviderScope(
      overrides: [
        activeHoldsProvider('').overrideWith((ref) async => holds),
        bookingStatsProvider('', '').overrideWith((ref) async => stats),
        availableProjectsProvider.overrideWith((ref) async => <ProjectRef>[]),
        ...extra,
      ],
      child: const MaterialApp(home: BookingDashboardScreen()),
    );

void main() {
  testWidgets('renders stats tiles + a hold with a countdown', (tester) async {
    await tester.pumpWidget(host(
      holds: [hold()],
      stats: const BookingStats(
        confirmedBookings: 1,
        activeHolds: 1,
        totalHolds: 2,
        conversionPct: 50,
      ),
    ));
    await tester.pump(); // resolve the futures
    await tester.pump();

    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Conversion'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Unit 102'), findsOneWidget);
    expect(find.text('Asha · rep1@x'), findsOneWidget);
    expect(find.text('Convert to sold'), findsOneWidget);
    // The reused countdown chip shows a "…left" label while comfortable.
    expect(find.textContaining('left'), findsWidgets);
  });

  testWidgets('single agent → no agent filter chips', (tester) async {
    await tester.pumpWidget(host(
      holds: [hold()],
      stats: BookingStats.empty,
    ));
    await tester.pump();
    await tester.pump();
    // Roster has one agent → the filter is hidden (nothing to choose between).
    expect(find.text('All agents'), findsNothing);
  });

  testWidgets('two agents → roster chips filter the holds list client-side',
      (tester) async {
    await tester.pumpWidget(host(
      holds: [
        hold(),
        hold(
            holdId: 'h2',
            unitNo: '103',
            leadName: 'Vikram',
            agentId: 'a2',
            agentName: 'rep2@y'),
      ],
      stats: const BookingStats(
        confirmedBookings: 1,
        activeHolds: 2,
        totalHolds: 3,
        conversionPct: 33.3,
      ),
      extra: [
        // stats re-fetch when agent 'a2' is selected
        bookingStatsProvider('', 'a2').overrideWith((ref) async =>
            const BookingStats(
                confirmedBookings: 0,
                activeHolds: 1,
                totalHolds: 1,
                conversionPct: 0)),
      ],
    ));
    await tester.pump();
    await tester.pump();

    // Both agents' holds and both roster chips render.
    expect(find.text('Unit 102'), findsOneWidget);
    expect(find.text('Unit 103'), findsOneWidget);
    expect(find.text('All agents'), findsOneWidget);
    expect(find.text('rep1@x'), findsOneWidget);
    expect(find.text('rep2@y'), findsOneWidget);

    // Selecting rep2 filters the list to that agent's hold only.
    await tester.tap(find.text('rep2@y'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Unit 102'), findsNothing);
    expect(find.text('Unit 103'), findsOneWidget);
  });

  testWidgets('empty scope shows a calm empty state', (tester) async {
    await tester.pumpWidget(host(holds: const [], stats: BookingStats.empty));
    await tester.pump();
    await tester.pump();
    expect(find.text('No active holds right now.'), findsOneWidget);
    expect(find.text('Convert to sold'), findsNothing);
  });
}
