// Story 12.4-mobile — regression: tier change that invalidates the current
// reports_to selection must not crash the reports-to dropdown.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/hierarchy/data/models/hierarchy_user.dart';
import 'package:nirman_crm/features/hierarchy/ui/edit_hierarchy_sheet.dart';

HierarchyUser mk(String id, RoleTier tier, {String? reportsTo}) => HierarchyUser(
      id: id,
      emailOrUsername: '$id@x',
      role: 'employee',
      roleTier: tier,
      reportsToUserId: reportsTo,
      agencyId: null,
      isExternal: false,
      isActive: true,
    );

void main() {
  testWidgets('leader→head (drops the only manager) does not assert-crash',
      (tester) async {
    final head = mk('head', RoleTier.builderHead);
    // A leader currently reporting to head — head is a valid manager for a leader.
    final leader = mk('lead', RoleTier.teamLeader, reportsTo: 'head');

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showEditHierarchySheet(
                context,
                user: leader,
                users: [head, leader],
                agencies: const [],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Sheet opens with head pre-selected as manager (leader→head is valid).
    expect(find.text('Reports to'), findsOneWidget);

    // Promote to Builder Head — now head (rank 3) is no longer strictly-higher,
    // so it leaves the manager options. The dropdown must not hold a stale value.
    await tester.tap(find.text('Team Leader'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Builder Head').last);
    await tester.pumpAndSettle();

    // No exception thrown; reports-to still present (Builder Head is a ladder tier)
    // and now shows the None sentinel with no valid managers.
    expect(tester.takeException(), isNull);
    expect(find.text('Reports to'), findsOneWidget);
    expect(find.text('No higher-tier users to report to yet.'), findsOneWidget);
  });
}
