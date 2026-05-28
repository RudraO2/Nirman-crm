// Story 2.8 — LeadListItem.fromJson parses archived_at from get_my_archived_leads.
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/leads/data/models/lead_model.dart';

void main() {
  Map<String, dynamic> baseRow({
    String? archivedAt,
    String status = 'sold',
  }) => {
        'id': '4e6c1c18-8f58-4fc4-ab0d-d73b69deff15',
        'status': status,
        'name': 'Rudra',
        'phone': '9166921692',
        'source': null,
        'property_type': null,
        'location': null,
        'budget_min': null,
        'budget_max': null,
        'ticket_size': null,
        'visit_date': null,
        'next_followup_at': null,
        'is_incomplete': false,
        'pending_outcome_at': null,
        'last_action_at': null,
        'created_at': '2026-05-27T19:06:50.061154+00:00',
        'urgency_score': 0,
        'interest_type': null,
        if (archivedAt != null) 'archived_at': archivedAt,
      };

  test('parses archived_at when present', () {
    final l = LeadListItem.fromJson(baseRow(archivedAt: '2026-05-28T03:56:42.956931+00:00'));
    expect(l.archivedAt, isNotNull);
    expect(l.archivedAt!.toUtc().year, 2026);
    expect(l.status, 'sold');
  });

  test('archivedAt is null when key absent (active-list row)', () {
    final l = LeadListItem.fromJson(baseRow());
    expect(l.archivedAt, isNull);
  });

  test('archivedAt is null when explicit null', () {
    final row = baseRow();
    row['archived_at'] = null;
    final l = LeadListItem.fromJson(row);
    expect(l.archivedAt, isNull);
  });
}
