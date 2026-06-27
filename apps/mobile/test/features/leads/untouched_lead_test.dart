// Untouched-lead detection — distinguishes bulk-imported/never-worked leads from
// ones the employee has actioned. "warm" status alone is NOT a touched signal
// (import defaults everything to warm); last_action_at vs created_at is.
// Run with: flutter test test/features/leads/untouched_lead_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/leads/data/models/lead_model.dart';
import 'package:nirman_crm/features/leads/ui/filtered_leads_screen.dart';

LeadListItem lead({
  required DateTime createdAt,
  DateTime? lastActionAt,
  DateTime? pendingOutcomeAt,
  String status = 'warm',
}) =>
    LeadListItem(
      id: 'x',
      status: status,
      isIncomplete: true,
      createdAt: createdAt,
      lastActionAt: lastActionAt,
      pendingOutcomeAt: pendingOutcomeAt,
      urgencyScore: 300,
    );

void main() {
  final t0 = DateTime(2026, 6, 1, 8, 0, 0);

  group('LeadListItem.isUntouched', () {
    test('last_action == created → untouched (imported, never worked)', () {
      expect(lead(createdAt: t0, lastActionAt: t0).isUntouched, isTrue);
    });

    test('last_action null → untouched', () {
      expect(lead(createdAt: t0, lastActionAt: null).isUntouched, isTrue);
    });

    test('within 2s skew of created → still untouched', () {
      expect(
        lead(createdAt: t0, lastActionAt: t0.add(const Duration(seconds: 2)))
            .isUntouched,
        isTrue,
      );
    });

    test('last_action clearly after created → touched', () {
      expect(
        lead(createdAt: t0, lastActionAt: t0.add(const Duration(minutes: 5)))
            .isUntouched,
        isFalse,
      );
    });

    test('pending outcome (was called) → never untouched', () {
      expect(
        lead(createdAt: t0, lastActionAt: t0, pendingOutcomeAt: t0).isUntouched,
        isFalse,
      );
    });

    test('warm status does not by itself mean touched', () {
      // The whole point: a warm lead can still be untouched.
      expect(lead(createdAt: t0, lastActionAt: t0, status: 'warm').isUntouched,
          isTrue);
    });
  });

  group('LeadFilter.untouched.apply', () {
    test('keeps only untouched leads', () {
      final touched = lead(
          createdAt: t0, lastActionAt: t0.add(const Duration(hours: 1)));
      final untouchedA = lead(createdAt: t0, lastActionAt: t0);
      final untouchedB = lead(createdAt: t0, lastActionAt: null);
      final called = lead(createdAt: t0, lastActionAt: t0, pendingOutcomeAt: t0);

      final out = LeadFilter.untouched
          .apply([touched, untouchedA, untouchedB, called]);

      expect(out.length, 2);
      expect(out, containsAll([untouchedA, untouchedB]));
      expect(out, isNot(contains(touched)));
      expect(out, isNot(contains(called)));
    });
  });
}
