// Story 12.6-mobile — TeamLead + owner helpers pure-logic tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/team/data/models/team_lead.dart';
import 'package:nirman_crm/features/team/data/team_repository.dart';

Map<String, dynamic> row({
  required String id,
  required String status,
  String? owner,
  String? name,
}) =>
    {
      'id': id,
      'status': status,
      'assigned_to_user_id': owner,
      'name': name,
      'phone': '9876543210',
      'is_incomplete': false,
      'created_at': '2026-07-01T10:00:00Z',
      'urgency_score': 500,
      // NB: get_team_leads omits interest_type / archived_at / is_shared entirely.
    };

void main() {
  group('TeamLead.fromJson', () {
    test('maps the lead body + owner id, tolerating omitted columns', () {
      final t = TeamLead.fromJson(
          row(id: 'l1', status: 'hot', owner: 'u9', name: 'Asha'));
      expect(t.id, 'l1');
      expect(t.ownerId, 'u9');
      expect(t.lead.status, 'hot');
      expect(t.lead.name, 'Asha');
      expect(t.lead.isShared, isFalse); // absent key → default false
      expect(t.lead.interestType, isNull); // absent key → null
    });

    test('null owner id tolerated', () {
      final t = TeamLead.fromJson(row(id: 'l2', status: 'warm', owner: null));
      expect(t.ownerId, isNull);
    });
  });

  group('distinctOwnerIds', () {
    test('collects distinct non-null/non-empty ids (bounded lookup input)', () {
      final leads = [
        TeamLead.fromJson(row(id: 'a', status: 'hot', owner: 'u1')),
        TeamLead.fromJson(row(id: 'b', status: 'cold', owner: 'u1')), // dup
        TeamLead.fromJson(row(id: 'c', status: 'warm', owner: 'u2')),
        TeamLead.fromJson(row(id: 'd', status: 'warm', owner: null)),
        TeamLead.fromJson(row(id: 'e', status: 'warm', owner: '')),
      ];
      expect(distinctOwnerIds(leads), {'u1', 'u2'});
    });

    test('empty list → empty set', () {
      expect(distinctOwnerIds(const []), isEmpty);
    });
  });

  group('ownerLabel', () {
    test('resolved name wins', () {
      expect(ownerLabel('u1', {'u1': 'lead@x'}), 'lead@x');
    });
    test('unresolved id → masked Teammate label (no raw uuid)', () {
      final l = ownerLabel('abcd1234-ef', const {});
      expect(l, 'Teammate ·abcd');
      expect(l.contains('1234-ef'), isFalse);
    });
    test('null / empty owner → Unassigned', () {
      expect(ownerLabel(null, const {}), 'Unassigned');
      expect(ownerLabel('', const {}), 'Unassigned');
    });
  });

  group('TeamAccessException', () {
    test('not_authenticated → sign-in message', () {
      const e = TeamAccessException('not_authenticated', notAuthenticated: true);
      expect(e.friendly, contains('sign in'));
    });
    test('generic → pull-to-refresh message', () {
      const e = TeamAccessException('random pg error');
      expect(e.friendly, contains('refresh'));
    });
  });
}
