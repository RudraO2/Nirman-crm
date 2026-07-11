// Story 15.5-mobile — ActiveHold parsing + neutral labels.

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/booking/data/models/active_hold.dart';

Map<String, dynamic> row({String? leadName, String? agentName}) => {
      'hold_id': 'h1',
      'unit_id': 'u1',
      'unit_no': '102',
      'project_id': 'p1',
      'lead_id': 'l1',
      'lead_name': leadName,
      'holding_agent_id': 'a1',
      'agent_name': agentName,
      'held_at': '2026-07-11T09:00:00Z',
      'expires_at': '2026-07-12T09:00:00Z',
      'seconds_to_expiry': 86400,
    };

void main() {
  test('fromJson maps every column', () {
    final h = ActiveHold.fromJson(row(leadName: 'Asha', agentName: 'rep1@x'));
    expect(h.holdId, 'h1');
    expect(h.unitNo, '102');
    expect(h.leadName, 'Asha');
    expect(h.agentName, 'rep1@x');
    expect(h.secondsToExpiry, 86400);
    expect(h.expiresAt.toUtc().hour, 9);
  });

  test('null lead/agent names fall back to neutral labels (PII-safe)', () {
    final h = ActiveHold.fromJson(row());
    expect(h.leadName, isNull);
    expect(h.leadLabel, 'Lead');
    expect(h.agentLabel, 'Agent');
  });

  test('resolved names are used when present', () {
    final h = ActiveHold.fromJson(row(leadName: 'Asha', agentName: 'rep1@x'));
    expect(h.leadLabel, 'Asha');
    expect(h.agentLabel, 'rep1@x');
  });
}
