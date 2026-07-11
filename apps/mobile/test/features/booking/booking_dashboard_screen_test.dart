// Story 15.5-mobile — dashboard renders stats tiles + active holds (with a live
// countdown) and a calm empty state. Providers are overridden with fakes; we pump
// single frames (HoldCountdown runs a 1 Hz Timer, so pumpAndSettle would hang).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/booking/data/models/active_hold.dart';
import 'package:nirman_crm/features/booking/data/models/booking_stats.dart';
import 'package:nirman_crm/features/booking/providers/booking_providers.dart';
import 'package:nirman_crm/features/booking/ui/booking_dashboard_screen.dart';
import 'package:nirman_crm/features/leads/data/models/lead_model.dart';
import 'package:nirman_crm/features/leads/providers/lead_providers.dart';

ActiveHold hold() => ActiveHold.fromJson({
      'hold_id': 'h1',
      'unit_id': 'u1',
      'unit_no': '102',
      'project_id': 'p1',
      'lead_id': 'l1',
      'lead_name': 'Asha',
      'holding_agent_id': 'a1',
      'agent_name': 'rep1@x',
      'held_at': DateTime.now().toUtc().toIso8601String(),
      'expires_at':
          DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String(),
      'seconds_to_expiry': 18000,
    });

Widget host({
  required List<ActiveHold> holds,
  required BookingStats stats,
}) =>
    ProviderScope(
      overrides: [
        activeHoldsProvider('').overrideWith((ref) async => holds),
        bookingStatsProvider('').overrideWith((ref) async => stats),
        availableProjectsProvider.overrideWith((ref) async => <ProjectRef>[]),
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

  testWidgets('empty scope shows a calm empty state', (tester) async {
    await tester.pumpWidget(host(holds: const [], stats: BookingStats.empty));
    await tester.pump();
    await tester.pump();
    expect(find.text('No active holds right now.'), findsOneWidget);
    expect(find.text('Convert to sold'), findsNothing);
  });
}
