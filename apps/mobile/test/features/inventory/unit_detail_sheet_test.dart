// Story 14.3 + 15.2 mobile — detail sheet: margin visibility + Hold button gating.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/inventory/data/models/unit_hold_model.dart';
import 'package:nirman_crm/features/inventory/data/models/unit_model.dart';
import 'package:nirman_crm/features/inventory/providers/inventory_providers.dart';
import 'package:nirman_crm/features/inventory/ui/unit_detail_sheet.dart';

ProjectUnit unit({int? costPaise, UnitStatus status = UnitStatus.available}) =>
    ProjectUnit(
      unitId: 'u1',
      towerId: 't1',
      towerName: 'Tower A',
      unitNo: 'A-301',
      floor: 3,
      configuration: '2BHK',
      carpetAreaSqft: 845,
      status: status,
      listPricePaise: 7500000000,
      costPaise: costPaise,
      statusVersion: 1,
    );

void main() {
  Widget host(ProjectUnit u) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: UnitDetailSheet(unit: u, projectId: 'p1'),
          ),
        ),
      );

  testWidgets('shows margin row for head (costPaise present)', (tester) async {
    await tester.pumpWidget(host(unit(costPaise: 4000000000)));
    expect(find.text('Cost (margin)'), findsOneWidget);
    expect(find.text('Unit A-301'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
  });

  testWidgets('hides margin row when costPaise null (non-head)', (tester) async {
    await tester.pumpWidget(host(unit(costPaise: null)));
    expect(find.text('Cost (margin)'), findsNothing);
    expect(find.text('List price'), findsOneWidget);
  });

  testWidgets('Hold button ENABLED for an available unit', (tester) async {
    await tester.pumpWidget(host(unit(status: UnitStatus.available)));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
    expect(find.text('Hold this unit'), findsOneWidget);
  });

  testWidgets('Hold button DISABLED for a sold unit', (tester) async {
    await tester.pumpWidget(host(unit(status: UnitStatus.sold)));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Unavailable'), findsOneWidget);
  });

  testWidgets('held unit with a lead shows Confirm + Log amendment', (tester) async {
    final u = unit(status: UnitStatus.hold);
    final hold = UnitHold(
      holdId: 'h1',
      unitId: 'u1',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
      leadId: 'l1',
      holdingAgentId: 'a1',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [activeHoldProvider('u1').overrideWith((ref) async => hold)],
        child: MaterialApp(
          home: Scaffold(body: UnitDetailSheet(unit: u, projectId: 'p1')),
        ),
      ),
    );
    await tester.pump(); // resolve the hold future
    await tester.pump();
    expect(find.text('Confirm booking'), findsOneWidget);
    expect(find.text('Log amendment'), findsOneWidget);
  });
}
