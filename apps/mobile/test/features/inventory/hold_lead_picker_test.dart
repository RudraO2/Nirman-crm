// Story 15.2-mobile — the hold lead-picker now sources team-scoped leads
// (teamLeadsProvider / get_team_leads) instead of the caller's own leads, so a
// builder_head / team_leader can hold a unit for any lead in their visible scope.
// These tests lock: (1) the picker renders the team leads with owner labels, and
// (2) tapping a row returns that LeadListItem to the caller.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/inventory/ui/hold_lead_picker_sheet.dart';
import 'package:nirman_crm/features/leads/data/models/lead_model.dart';
import 'package:nirman_crm/features/team/data/models/team_lead.dart';
import 'package:nirman_crm/features/team/providers/team_providers.dart';

TeamLead lead(String id, String owner, String name) => TeamLead.fromJson({
      'id': id,
      'status': 'hot',
      'assigned_to_user_id': owner,
      'name': name,
      'phone': '9876543210',
      'is_incomplete': false,
      'created_at': '2026-07-01T10:00:00Z',
      'urgency_score': 500,
    });

/// Hosts a button that opens the picker and records the returned lead.
Widget host({
  required List<TeamLead> leads,
  required Map<String, String> names,
  required void Function(LeadListItem?) onResult,
}) =>
    ProviderScope(
      overrides: [
        teamLeadsProvider.overrideWith((ref) async => leads),
        ownerNamesProvider.overrideWith((ref) async => names),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => onResult(await showHoldLeadPicker(ctx)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('lists team leads with owner labels (resolved + masked)',
      (tester) async {
    await tester.pumpWidget(host(
      leads: [lead('l1', 'u1', 'Asha'), lead('l2', 'uABCD99', 'Vikram')],
      names: {'u1': 'leader@x'},
      onResult: (_) {},
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Hold for which lead?'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Vikram'), findsOneWidget);
    // subtitle = "<phone> · <owner label>"; u1 resolves, uABCD99 masks.
    expect(find.text('9876543210 · leader@x'), findsOneWidget);
    expect(find.text('9876543210 · Teammate ·uABC'), findsOneWidget);
  });

  testWidgets('tapping a row returns that lead to the caller', (tester) async {
    LeadListItem? picked;
    await tester.pumpWidget(host(
      leads: [lead('l1', 'u1', 'Asha'), lead('l2', 'u1', 'Vikram')],
      names: {'u1': 'leader@x'},
      onResult: (r) => picked = r,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vikram'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.id, 'l2');
  });
}
