// Story 15.2-mobile — UnitHold parsing, countdown formatter, hold-error mapping.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nirman_crm/features/inventory/data/inventory_repository.dart';
import 'package:nirman_crm/features/inventory/data/models/unit_hold_model.dart';
import 'package:nirman_crm/features/inventory/ui/hold_countdown.dart';

void main() {
  group('HoldException.fromPostgrest', () {
    HoldException map(String message) =>
        HoldException.fromPostgrest(PostgrestException(message: message));

    test('unit_unavailable → conflict', () {
      final e = map('unit_unavailable');
      expect(e.conflict, isTrue);
      expect(e.notAllowed, isFalse);
    });
    test('receptionist permission_denied → notAllowed', () {
      final e = map('permission_denied: receptionist cannot hold units');
      expect(e.notAllowed, isTrue);
      expect(e.conflict, isFalse);
    });
    test('not_your_lead → notAllowed', () {
      expect(map('not_your_lead').notAllowed, isTrue);
    });
    test('unknown → generic (neither flag)', () {
      final e = map('hold_timer_not_configured');
      expect(e.conflict, isFalse);
      expect(e.notAllowed, isFalse);
    });
  });

  group('UnitHold.fromRpc', () {
    test('parses the hold_unit jsonb result', () {
      final h = UnitHold.fromRpc({
        'hold_id': 'h1',
        'unit_id': 'u1',
        'status_version': 3,
        'expires_at': '2026-07-11T10:00:00+00:00',
      });
      expect(h.holdId, 'h1');
      expect(h.unitId, 'u1');
      expect(h.statusVersion, 3);
      expect(h.expiresAt.toUtc().hour, 10);
    });

    test('parses a unit_holds table row', () {
      final h = UnitHold.fromRow({
        'id': 'h9',
        'unit_id': 'u1',
        'lead_id': 'l1',
        'holding_agent_id': 'a1',
        'expires_at': '2026-07-11T10:00:00+00:00',
      });
      expect(h.holdId, 'h9');
      expect(h.leadId, 'l1');
      expect(h.holdingAgentId, 'a1');
    });
  });

  group('formatRemaining', () {
    test('hours + minutes', () {
      expect(formatRemaining(const Duration(hours: 23, minutes: 58)), '23h 58m left');
    });
    test('minutes + seconds under an hour', () {
      expect(formatRemaining(const Duration(minutes: 5, seconds: 30)), '5m 30s left');
    });
    test('seconds only', () {
      expect(formatRemaining(const Duration(seconds: 9)), '9s left');
    });
    test('zero or negative → Expired', () {
      expect(formatRemaining(Duration.zero), 'Expired');
      expect(formatRemaining(const Duration(seconds: -5)), 'Expired');
    });
  });
}
