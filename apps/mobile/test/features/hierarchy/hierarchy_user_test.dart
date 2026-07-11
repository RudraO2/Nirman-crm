// Story 12.4-mobile — HierarchyUser + RoleTier + managerOptionsFor pure-logic tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/hierarchy/data/models/hierarchy_user.dart';

void main() {
  group('RoleTier.fromDb', () {
    test('maps every known db value', () {
      expect(RoleTier.fromDb('super_admin'), RoleTier.superAdmin);
      expect(RoleTier.fromDb('builder_head'), RoleTier.builderHead);
      expect(RoleTier.fromDb('team_leader'), RoleTier.teamLeader);
      expect(RoleTier.fromDb('front_line_rep'), RoleTier.frontLineRep);
      expect(RoleTier.fromDb('partner_agency'), RoleTier.partnerAgency);
      expect(RoleTier.fromDb('receptionist'), RoleTier.receptionist);
    });

    test('null / unrecognised → unknown (never matches empty dbValue)', () {
      expect(RoleTier.fromDb(null), RoleTier.unknown);
      expect(RoleTier.fromDb(''), RoleTier.unknown);
      expect(RoleTier.fromDb('emperor'), RoleTier.unknown);
    });
  });

  group('RoleTier ranks & ladder', () {
    test('ranks are strictly ordered on the ladder', () {
      expect(RoleTier.superAdmin.rank, greaterThan(RoleTier.builderHead.rank));
      expect(RoleTier.builderHead.rank, greaterThan(RoleTier.teamLeader.rank));
      expect(RoleTier.teamLeader.rank, greaterThan(RoleTier.frontLineRep.rank));
    });

    test('off-ladder tiers are rank 0 and not ladder', () {
      expect(RoleTier.partnerAgency.rank, 0);
      expect(RoleTier.receptionist.rank, 0);
      expect(RoleTier.partnerAgency.isLadder, isFalse);
      expect(RoleTier.receptionist.isLadder, isFalse);
      expect(RoleTier.frontLineRep.isLadder, isTrue);
    });

    test('selectable excludes unknown', () {
      expect(RoleTier.selectable.contains(RoleTier.unknown), isFalse);
      expect(RoleTier.selectable.length, 6);
    });
  });

  group('HierarchyUser.fromJson', () {
    test('maps all columns including nulls', () {
      final u = HierarchyUser.fromJson({
        'id': 'u1',
        'email_or_username': 'rep@x',
        'role': 'employee',
        'role_tier': null,
        'reports_to_user_id': null,
        'agency_id': null,
        'is_external': null,
        'is_active': null,
      });
      expect(u.id, 'u1');
      expect(u.emailOrUsername, 'rep@x');
      expect(u.roleTier, RoleTier.unknown);
      expect(u.reportsToUserId, isNull);
      expect(u.agencyId, isNull);
      expect(u.isExternal, isFalse); // null → false
      expect(u.isActive, isTrue); // null → true
    });

    test('maps a partner user', () {
      final u = HierarchyUser.fromJson({
        'id': 'p1',
        'email_or_username': 'partner@x',
        'role': 'employee',
        'role_tier': 'partner_agency',
        'reports_to_user_id': null,
        'agency_id': 'ag1',
        'is_external': true,
        'is_active': true,
      });
      expect(u.roleTier, RoleTier.partnerAgency);
      expect(u.isExternal, isTrue);
      expect(u.agencyId, 'ag1');
    });
  });

  group('managerOptionsFor', () {
    HierarchyUser mk(String id, RoleTier tier) => HierarchyUser(
          id: id,
          emailOrUsername: '$id@x',
          role: 'employee',
          roleTier: tier,
          reportsToUserId: null,
          agencyId: null,
          isExternal: false,
          isActive: true,
        );

    final users = [
      mk('head', RoleTier.builderHead),
      mk('lead', RoleTier.teamLeader),
      mk('rep', RoleTier.frontLineRep),
      mk('rep2', RoleTier.frontLineRep),
      mk('partner', RoleTier.partnerAgency),
    ];

    test('rep can report to leader and head only (strictly higher ladder)', () {
      final opts = managerOptionsFor(
          tier: RoleTier.frontLineRep, editingUserId: 'rep', allUsers: users);
      final ids = opts.map((u) => u.id).toSet();
      expect(ids, {'head', 'lead'});
      expect(ids.contains('rep2'), isFalse); // same rank excluded
      expect(ids.contains('partner'), isFalse); // off-ladder excluded
    });

    test('leader can report to head only', () {
      final opts = managerOptionsFor(
          tier: RoleTier.teamLeader, editingUserId: 'lead', allUsers: users);
      expect(opts.map((u) => u.id), ['head']);
    });

    test('excludes self even if a same-tier candidate', () {
      final opts = managerOptionsFor(
          tier: RoleTier.frontLineRep, editingUserId: 'rep', allUsers: users);
      expect(opts.any((u) => u.id == 'rep'), isFalse);
    });

    test('off-ladder tier yields no manager options', () {
      expect(
        managerOptionsFor(
            tier: RoleTier.partnerAgency,
            editingUserId: 'partner',
            allUsers: users),
        isEmpty,
      );
      expect(
        managerOptionsFor(
            tier: RoleTier.receptionist,
            editingUserId: 'x',
            allUsers: users),
        isEmpty,
      );
    });

    test('head has no higher tier to report to', () {
      final opts = managerOptionsFor(
          tier: RoleTier.builderHead, editingUserId: 'head', allUsers: users);
      // only super_admin would qualify; none present
      expect(opts, isEmpty);
    });
  });
}
