// Story 9.6 — pure billing/lockout/warning logic tests (no backend, no plugins).
// The lockout itself is server-enforced (0056 + 0092); these cover the client's
// interpretation of get_my_billing_status() that picks screen vs banner vs normal.

import 'package:flutter_test/flutter_test.dart';
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
      expect(s.isExpiringSoon, isFalse);
    });

    test('null paid_until / days_remaining is tolerated', () {
      final s = BillingStatus.fromJson({'status': 'trial'});
      expect(s.isLockedOut, isFalse);
      expect(s.paidUntil, isNull);
      expect(s.daysRemaining, isNull);
      expect(s.isOverdue, isFalse);
      expect(s.isExpiringSoon, isFalse);
    });
  });

  group('isLockedOut mirrors the 0056/0092 chokepoint', () {
    test('active and trial are the only allowed states', () {
      expect(const BillingStatus(status: 'active').isLockedOut, isFalse);
      expect(const BillingStatus(status: 'trial').isLockedOut, isFalse);
    });
    test('suspended / cancelled / unknown are locked out', () {
      expect(const BillingStatus(status: 'suspended').isLockedOut, isTrue);
      expect(const BillingStatus(status: 'cancelled').isLockedOut, isTrue);
      expect(const BillingStatus(status: 'unknown').isLockedOut, isTrue);
    });
  });

  group('isOverdue', () {
    test('negative days_remaining is overdue', () {
      expect(
          const BillingStatus(status: 'suspended', daysRemaining: -3).isOverdue,
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

  group('isExpiringSoon (3-day advance warning)', () {
    test('active within the window (0..3 days) warns', () {
      expect(const BillingStatus(status: 'active', daysRemaining: 3)
          .isExpiringSoon, isTrue);
      expect(const BillingStatus(status: 'active', daysRemaining: 1)
          .isExpiringSoon, isTrue);
      expect(const BillingStatus(status: 'active', daysRemaining: 0)
          .isExpiringSoon, isTrue);
    });
    test('outside the window does not warn', () {
      expect(const BillingStatus(status: 'active', daysRemaining: 4)
          .isExpiringSoon, isFalse);
      expect(const BillingStatus(status: 'active', daysRemaining: 30)
          .isExpiringSoon, isFalse);
    });
    test('locked-out or overdue is NOT a warning (that is the lockout state)', () {
      expect(const BillingStatus(status: 'suspended', daysRemaining: 2)
          .isExpiringSoon, isFalse);
      expect(const BillingStatus(status: 'active', daysRemaining: -1)
          .isExpiringSoon, isFalse);
    });
    test('null days_remaining does not warn', () {
      expect(const BillingStatus(status: 'active').isExpiringSoon, isFalse);
    });
  });
}
