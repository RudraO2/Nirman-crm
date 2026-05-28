// Story 2.4 / 2.5 / 2.6 / 2.7 — Lead model unit tests.
// Pure-Dart contracts: fromJson parsing, computed properties, toJson serialisation.
// Run with: flutter test test/features/leads/lead_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/leads/data/models/lead_model.dart';

void main() {
  // ── LeadListItem.fromJson ────────────────────────────────────────────────

  group('LeadListItem.fromJson', () {
    final base = {
      'id': 'abc-123',
      'status': 'hot',
      'name': 'Ravi Kumar',
      'phone': '9876543210',
      'source': 'walk_in',
      'property_type': '3BHK',
      'location': 'Andheri',
      'budget_min': 5000000,
      'budget_max': 8000000,
      'ticket_size': '50L',
      'visit_date': '2026-06-01T10:00:00.000Z',
      'next_followup_at': '2026-05-28T09:00:00.000Z',
      'is_incomplete': false,
      'pending_outcome_at': null,
      'last_action_at': '2026-05-27T08:00:00.000Z',
      'created_at': '2026-05-20T08:00:00.000Z',
      'urgency_score': 300,
    };

    test('parses all fields', () {
      final item = LeadListItem.fromJson(base);
      expect(item.id, 'abc-123');
      expect(item.status, 'hot');
      expect(item.name, 'Ravi Kumar');
      expect(item.phone, '9876543210');
      expect(item.source, 'walk_in');
      expect(item.budgetMin, 5000000);
      expect(item.budgetMax, 8000000);
      expect(item.isIncomplete, false);
      expect(item.urgencyScore, 300);
    });

    test('handles null optional fields', () {
      final sparse = {
        'id': 'xyz',
        'status': 'cold',
        'name': null,
        'phone': null,
        'source': null,
        'property_type': null,
        'location': null,
        'budget_min': null,
        'budget_max': null,
        'ticket_size': null,
        'visit_date': null,
        'next_followup_at': null,
        'is_incomplete': true,
        'pending_outcome_at': null,
        'last_action_at': null,
        'created_at': '2026-05-20T00:00:00.000Z',
        'urgency_score': 50,
      };
      final item = LeadListItem.fromJson(sparse);
      expect(item.name, isNull);
      expect(item.phone, isNull);
      expect(item.visitDate, isNull);
      expect(item.isIncomplete, true);
    });

    test('parses datetime fields as UTC', () {
      final item = LeadListItem.fromJson(base);
      expect(item.visitDate, isNotNull);
      expect(item.nextFollowupAt, isNotNull);
      expect(item.createdAt.year, 2026);
    });
  });

  // ── LeadListItem computed properties ────────────────────────────────────

  group('LeadListItem.displayPhone', () {
    LeadListItem _make(String? phone) => LeadListItem(
          id: 'x', status: 'cold', phone: phone,
          isIncomplete: false, createdAt: DateTime.now(), urgencyScore: 0,
        );

    test('formats 10-digit phone with space at position 5', () {
      expect(_make('9876543210').displayPhone, '98765 43210');
    });

    test('returns raw string when phone is short', () {
      expect(_make('12345').displayPhone, '12345');
    });

    test('returns empty string when phone is null', () {
      expect(_make(null).displayPhone, '');
    });
  });

  group('LeadListItem.isStale', () {
    test('false when last action < 7 days ago', () {
      final item = LeadListItem(
        id: 'x', status: 'warm', isIncomplete: false,
        createdAt: DateTime.now(), urgencyScore: 0,
        lastActionAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect(item.isStale, false);
    });

    test('true when last action >= 7 days ago', () {
      final item = LeadListItem(
        id: 'x', status: 'warm', isIncomplete: false,
        createdAt: DateTime.now(), urgencyScore: 0,
        lastActionAt: DateTime.now().subtract(const Duration(days: 8)),
      );
      expect(item.isStale, true);
    });

    test('false when lastActionAt is null', () {
      final item = LeadListItem(
        id: 'x', status: 'warm', isIncomplete: false,
        createdAt: DateTime.now(), urgencyScore: 0,
      );
      expect(item.isStale, false);
    });
  });

  group('LeadListItem.hasPendingOutcome', () {
    test('true when pendingOutcomeAt is set', () {
      final item = LeadListItem(
        id: 'x', status: 'hot', isIncomplete: false,
        createdAt: DateTime.now(), urgencyScore: 0,
        pendingOutcomeAt: DateTime.now(),
      );
      expect(item.hasPendingOutcome, true);
    });

    test('false when pendingOutcomeAt is null', () {
      final item = LeadListItem(
        id: 'x', status: 'hot', isIncomplete: false,
        createdAt: DateTime.now(), urgencyScore: 0,
      );
      expect(item.hasPendingOutcome, false);
    });
  });

  group('LeadListItem.hasOverdueFollowup', () {
    test('true when nextFollowupAt is in the past', () {
      final item = LeadListItem(
        id: 'x', status: 'warm', isIncomplete: false,
        createdAt: DateTime.now(), urgencyScore: 0,
        nextFollowupAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(item.hasOverdueFollowup, true);
    });

    test('false when nextFollowupAt is in the future', () {
      final item = LeadListItem(
        id: 'x', status: 'warm', isIncomplete: false,
        createdAt: DateTime.now(), urgencyScore: 0,
        nextFollowupAt: DateTime.now().add(const Duration(hours: 2)),
      );
      expect(item.hasOverdueFollowup, false);
    });
  });

  // ── LeadDetail.fromJson ──────────────────────────────────────────────────

  group('LeadDetail.fromJson', () {
    test('parses project_ids from list', () {
      final json = {
        'id': 'abc', 'status': 'warm', 'name': 'Test', 'phone': '9876543210',
        'source': null, 'property_type': null, 'location': null,
        'budget_min': null, 'budget_max': null, 'ticket_size': null,
        'visit_date': null, 'next_followup_at': null, 'is_incomplete': false,
        'pending_outcome_at': null, 'last_action_at': null,
        'created_at': '2026-05-20T00:00:00.000Z', 'urgency_score': 100,
        'project_ids': ['pid-1', 'pid-2'],
      };
      final detail = LeadDetail.fromJson(json);
      expect(detail.projectIds, ['pid-1', 'pid-2']);
    });

    test('returns empty list when project_ids is null', () {
      final json = {
        'id': 'abc', 'status': 'warm', 'name': null, 'phone': null,
        'source': null, 'property_type': null, 'location': null,
        'budget_min': null, 'budget_max': null, 'ticket_size': null,
        'visit_date': null, 'next_followup_at': null, 'is_incomplete': true,
        'pending_outcome_at': null, 'last_action_at': null,
        'created_at': '2026-05-20T00:00:00.000Z', 'urgency_score': 50,
        'project_ids': null,
      };
      final detail = LeadDetail.fromJson(json);
      expect(detail.projectIds, isEmpty);
    });
  });

  // ── MarkDeadResult.fromJson ──────────────────────────────────────────────

  group('MarkDeadResult.fromJson', () {
    test('parses previous_status', () {
      final result = MarkDeadResult.fromJson({'previous_status': 'hot'});
      expect(result.previousStatus, 'hot');
    });

    test('parses cold previous_status', () {
      final result = MarkDeadResult.fromJson({'previous_status': 'cold'});
      expect(result.previousStatus, 'cold');
    });
  });

  // ── RescheduleVisitResult.fromJson ───────────────────────────────────────

  group('RescheduleVisitResult.fromJson', () {
    test('parses reschedule_count and visit_date', () {
      final result = RescheduleVisitResult.fromJson({
        'reschedule_count': 2,
        'visit_date': '2026-06-03T10:00:00.000Z',
      });
      expect(result.rescheduleCount, 2);
      expect(result.visitDate.year, 2026);
      expect(result.visitDate.month, 6);
      expect(result.visitDate.day, 3);
    });
  });

  // ── UpdateLeadPayload.toJson ─────────────────────────────────────────────

  group('UpdateLeadPayload.toJson', () {
    test('always includes lead_id, status, phone, project_ids', () {
      final p = UpdateLeadPayload(
        leadId: 'lid', status: 'hot', phone: '9876543210',
      );
      final j = p.toJson();
      expect(j['lead_id'], 'lid');
      expect(j['status'], 'hot');
      expect(j['phone'], '9876543210');
      expect(j['project_ids'], isEmpty);
    });

    test('omits null optional fields from json', () {
      final p = UpdateLeadPayload(
        leadId: 'lid', status: 'warm', phone: '9876543210',
        name: null, location: null,
      );
      final j = p.toJson();
      expect(j.containsKey('name'), false);
      expect(j.containsKey('location'), false);
    });

    test('includes non-null optional fields', () {
      final p = UpdateLeadPayload(
        leadId: 'lid', status: 'hot', phone: '9876543210',
        name: 'Anita', location: 'Bandra',
        budgetMin: 5000000, budgetMax: 10000000,
      );
      final j = p.toJson();
      expect(j['name'], 'Anita');
      expect(j['location'], 'Bandra');
      expect(j['budget_min'], 5000000);
      expect(j['budget_max'], 10000000);
    });
  });

  // ── UpdateLeadResult.fromJson ────────────────────────────────────────────

  group('UpdateLeadResult.fromJson', () {
    test('parses all fields including changed_fields list', () {
      final result = UpdateLeadResult.fromJson({
        'lead_id': 'lid',
        'is_incomplete': false,
        'status': 'hot',
        'changed_fields': ['status', 'name'],
      });
      expect(result.leadId, 'lid');
      expect(result.isIncomplete, false);
      expect(result.changedFields, containsAll(['status', 'name']));
    });

    test('returns empty changed_fields list when null', () {
      final result = UpdateLeadResult.fromJson({
        'lead_id': 'lid',
        'is_incomplete': true,
        'status': 'cold',
        'changed_fields': null,
      });
      expect(result.changedFields, isEmpty);
    });
  });
}
