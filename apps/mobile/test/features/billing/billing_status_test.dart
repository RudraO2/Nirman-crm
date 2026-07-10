// Story 9.6 — pure billing/lockout logic tests (no backend, no plugins).
// Covers the two risky decisions: (1) BillingStatus interpretation of the
// get_my_billing_status() payload, (2) classifying a caught error as
// "tenant locked out" vs a generic error we must NOT misread as paused (AC #7).

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nirman_crm/features/billing/data/billing_repository.dart';

void main() {
  group('BillingStatus.fromJson', () {
    test('parses a full active payload', () {
      final s = BillingStatus.fromJson({
        'status': 'active',
        'plan_name': 'Standard Monthly',
        'paid_until': '2026-08-10T00:00:00Z',
        'days_remaining': 12,
      });
      expect(s.status, 'active');
      expect(s.planName, 'Standard Monthly');
      expect(s.paidUntil, isNotNull);
      expect(s.daysRemaining, 12);
      expect(s.isLockedOut, isFalse);
      expect(s.isOverdue, isFalse);
    });

    test('null paid_until / days_remaining is tolerated', () {
      final s = BillingStatus.fromJson({'status': 'trial'});
      expect(s.isLockedOut, isFalse);
      expect(s.paidUntil, isNull);
      expect(s.daysRemaining, isNull);
      expect(s.isOverdue, isFalse);
    });
  });

  group('BillingStatus.isLockedOut mirrors the 0056 chokepoint', () {
    test('active and trial are the only allowed states', () {
      expect(const BillingStatus(status: 'active').isLockedOut, isFalse);
      expect(const BillingStatus(status: 'trial').isLockedOut, isFalse);
    });

    test('suspended / cancelled / unknown are locked out', () {
      expect(const BillingStatus(status: 'suspended').isLockedOut, isTrue);
      expect(const BillingStatus(status: 'cancelled').isLockedOut, isTrue);
      expect(const BillingStatus(status: 'grace').isLockedOut, isTrue);
      expect(const BillingStatus(status: 'unknown').isLockedOut, isTrue);
    });
  });

  group('BillingStatus.isOverdue', () {
    test('negative days_remaining is overdue', () {
      expect(const BillingStatus(status: 'suspended', daysRemaining: -3).isOverdue,
          isTrue);
    });
    test('zero/positive/null is not overdue', () {
      expect(const BillingStatus(status: 'active', daysRemaining: 0).isOverdue,
          isFalse);
      expect(const BillingStatus(status: 'active', daysRemaining: 5).isOverdue,
          isFalse);
      expect(const BillingStatus(status: 'trial').isOverdue, isFalse);
    });
  });

  group('isTenantLockedOutError (AC #7 — no false positives)', () {
    test('P0001 code is a lockout signal', () {
      const e = PostgrestException(
          message: 'missing_tenant_context', code: 'P0001');
      expect(isTenantLockedOutError(e), isTrue);
    });

    test('message match alone is enough', () {
      const e = PostgrestException(
          message: 'error: missing_tenant_context', code: null);
      expect(isTenantLockedOutError(e), isTrue);
    });

    test('a different Postgrest error is NOT a lockout', () {
      const e = PostgrestException(message: 'permission denied', code: '42501');
      expect(isTenantLockedOutError(e), isFalse);
    });

    test('a generic/network error is NOT a lockout', () {
      expect(isTenantLockedOutError(Exception('SocketException')), isFalse);
    });
  });
}
