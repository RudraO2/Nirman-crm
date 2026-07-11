// Story 12.6-mobile — screen renders owner chips (resolved name + masked fallback)
// and a calm empty state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/team/data/models/team_lead.dart';
import 'package:nirman_crm/features/team/providers/team_providers.dart';
import 'package:nirman_crm/features/team/ui/team_leads_screen.dart';

TeamLead lead(String id, String status, String? owner, String name) =>
    TeamLead.fromJson({
      'id': id,
      'status': status,
      'assigned_to_user_id': owner,
      'name': name,
      'phone': '9876543210',
      'is_incomplete': false,
      'created_at': '2026-07-01T10:00:00Z',
      'urgency_score': 500,
    });

Widget host({
  required List<TeamLead> leads,
  required Map<String, String> names,
}) =>
    ProviderScope(
      overrides: [
        teamLeadsProvider.overrideWith((ref) async => leads),
        ownerNamesProvider.overrideWith((ref) async => names),
      ],
      child: const MaterialApp(home: TeamLeadsScreen()),
    );

void main() {
  testWidgets('renders resolved owner name and masked fallback', (tester) async {
    await tester.pumpWidget(host(
      leads: [
        lead('l1', 'hot', 'u1', 'Asha'),
        lead('l2', 'warm', 'uZZZZ9999', 'Vikram'),
      ],
      names: {'u1': 'leader@x'},
    ));
    await tester.pumpAndSettle();

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Vikram'), findsOneWidget);
    expect(find.text('Hot'), findsOneWidget);
    // u1 resolved to a name; uZZZZ9999 falls back to a masked label.
    expect(find.text('leader@x'), findsOneWidget);
    expect(find.text('Teammate ·uZZZ'), findsOneWidget);
  });

  testWidgets('empty scope shows a calm empty state (receptionist path)',
      (tester) async {
    await tester.pumpWidget(host(leads: const [], names: const {}));
    await tester.pumpAndSettle();
    expect(find.text('No team leads to show yet.'), findsOneWidget);
  });
}
