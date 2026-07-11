// Story 12.4-mobile — edit sheet: tier-dependent fields + partner-needs-agency guard.
//
// Drives the real modal via showEditHierarchySheet. The partner-no-agency case
// short-circuits in _save() BEFORE the repo is touched, so no provider override is
// needed — the sheet stays open and shows the inline error.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/hierarchy/data/models/hierarchy_user.dart';
import 'package:nirman_crm/features/hierarchy/ui/edit_hierarchy_sheet.dart';

HierarchyUser mk(String id, RoleTier tier, {bool external = false}) =>
    HierarchyUser(
      id: id,
      emailOrUsername: '$id@x',
      role: 'employee',
      roleTier: tier,
      reportsToUserId: null,
      agencyId: null,
      isExternal: external,
      isActive: true,
    );

void main() {
  final rep = mk('rep', RoleTier.frontLineRep);
  final head = mk('head', RoleTier.builderHead);

  Widget host({List<dynamic>? agencies}) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showEditHierarchySheet(
                  context,
                  user: rep,
                  users: [rep, head],
                  agencies: const [],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('ladder tier shows Reports-to; partner hides it and shows Agency',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Rep (ladder) → reports-to visible, no agency field.
    expect(find.text('Reports to'), findsOneWidget);
    expect(find.text('Agency *'), findsNothing);

    // Switch tier → Partner · Agency.
    await tester.tap(find.text('Front-line Rep'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partner · Agency').last);
    await tester.pumpAndSettle();

    expect(find.text('Reports to'), findsNothing);
    expect(find.text('Agency *'), findsOneWidget);
    expect(find.text('No agencies yet — create one first.'), findsOneWidget);
  });

  testWidgets('partner without agency blocks save with inline error',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Front-line Rep'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partner · Agency').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Sheet still open (save short-circuited before the repo) + calm error shown.
    expect(find.text('Choose an agency for this partner user.'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}
