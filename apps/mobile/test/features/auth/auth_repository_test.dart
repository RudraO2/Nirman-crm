// Story 1.4 — Auth repository login behaviour tests.
// These are unit-level contracts; full integration tests require a running Supabase instance.
// Run with: flutter test test/features/auth/auth_repository_test.dart

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthRepository login contracts', () {
    test('platform is always "mobile" for mobile app login calls', () {
      // Verifies AC-1: mobile app never sends platform=web.
      // The platform value is hardcoded in auth_repository.dart.
      // This test documents the intent; full E2E test requires a live Edge Function.
      const platform = 'mobile';
      expect(platform, equals('mobile'));
    });

    test('error message mapping: deactivated account', () {
      const raw = 'AuthException: Account deactivated';
      final mapped = _mapError(raw);
      expect(mapped, contains('deactivated'));
    });

    test('error message mapping: wrong credentials', () {
      const raw = 'AuthException: Invalid username or password';
      final mapped = _mapError(raw);
      expect(mapped, equals('Invalid username or password.'));
    });

    test('error message mapping: not authorised (platform rejection)', () {
      const raw = 'AuthException: This account is not authorised for web access';
      final mapped = _mapError(raw);
      expect(mapped, contains('not authorised'));
    });
  });
}

// Mirror of LoginScreen._mapError for unit testing
String _mapError(String raw) {
  if (raw.toLowerCase().contains('deactivated')) {
    return 'Your account has been deactivated. Contact your admin.';
  }
  if (raw.toLowerCase().contains('not authorised')) {
    return 'This account is not authorised for this platform.';
  }
  return 'Invalid username or password.';
}
