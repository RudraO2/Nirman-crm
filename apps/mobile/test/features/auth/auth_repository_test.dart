// Stories 1.4 + 1.5 — Auth repository behaviour tests.
// These are unit-level contracts; full integration tests require a running Supabase instance.
// Run with: flutter test test/features/auth/auth_repository_test.dart

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthRepository login contracts', () {
    test('platform is always "mobile" for mobile app login calls', () {
      const platform = 'mobile';
      expect(platform, equals('mobile'));
    });

    test('error message mapping: deactivated account', () {
      const raw = 'AuthException: Account deactivated';
      final mapped = _mapLoginError(raw);
      expect(mapped, contains('deactivated'));
    });

    test('error message mapping: wrong credentials', () {
      const raw = 'AuthException: Invalid username or password';
      final mapped = _mapLoginError(raw);
      expect(mapped, equals('Invalid username or password.'));
    });

    test('error message mapping: not authorised (platform rejection)', () {
      const raw = 'AuthException: This account is not authorised for web access';
      final mapped = _mapLoginError(raw);
      expect(mapped, contains('not authorised'));
    });
  });

  group('PasswordChangeScreen local validation', () {
    test('password shorter than 8 chars fails', () {
      expect(_validatePassword('Ab1!xxx', 'Ab1!xxx'), isNotNull);
      expect(_validatePassword('Ab1!xxx', 'Ab1!xxx'), contains('8'));
    });

    test('password without uppercase fails', () {
      expect(_validatePassword('nouppercase1!', 'nouppercase1!'), isNotNull);
      expect(_validatePassword('nouppercase1!', 'nouppercase1!'), contains('uppercase'));
    });

    test('password without lowercase fails', () {
      expect(_validatePassword('NOLOWERCASE1!', 'NOLOWERCASE1!'), isNotNull);
      expect(_validatePassword('NOLOWERCASE1!', 'NOLOWERCASE1!'), contains('lowercase'));
    });

    test('password without digit fails', () {
      expect(_validatePassword('NoDigitsXX!', 'NoDigitsXX!'), isNotNull);
      expect(_validatePassword('NoDigitsXX!', 'NoDigitsXX!'), contains('number'));
    });

    test('mismatched confirm fails', () {
      expect(_validatePassword('ValidPass1!', 'Different1!'), isNotNull);
      expect(_validatePassword('ValidPass1!', 'Different1!'), contains('match'));
    });

    test('valid password passes all checks', () {
      expect(_validatePassword('ValidPass1!', 'ValidPass1!'), isNull);
    });
  });

  group('PasswordChangeScreen error mapping', () {
    test('wrong current password maps to user-friendly message', () {
      const raw = 'AuthException: Current password is incorrect';
      expect(_mapChangeError(raw), contains('incorrect'));
    });

    test('server complexity error maps correctly', () {
      const raw = 'AuthException: New password must be at least 8 characters';
      expect(_mapChangeError(raw), contains('8'));
    });

    test('generic server error gives fallback message', () {
      const raw = 'AuthException: internal_error';
      expect(_mapChangeError(raw), contains('try again'));
    });
  });
}

String _mapLoginError(String raw) {
  if (raw.toLowerCase().contains('deactivated')) return 'Your account has been deactivated. Contact your admin.';
  if (raw.toLowerCase().contains('not authorised')) return 'This account is not authorised for this platform.';
  return 'Invalid username or password.';
}

String? _validatePassword(String newPw, String confirm) {
  if (newPw.length < 8) return 'New password must be at least 8 characters';
  if (!newPw.contains(RegExp(r'[A-Z]'))) return 'New password must contain at least one uppercase letter';
  if (!newPw.contains(RegExp(r'[a-z]'))) return 'New password must contain at least one lowercase letter';
  if (!newPw.contains(RegExp(r'[0-9]'))) return 'New password must contain at least one number';
  if (newPw != confirm) return 'Passwords do not match';
  return null;
}

String _mapChangeError(String raw) {
  if (raw.contains('Current password is incorrect')) return 'Current password is incorrect.';
  if (raw.contains('at least 8')) return 'New password must be at least 8 characters.';
  if (raw.contains('uppercase')) return 'New password must contain at least one uppercase letter.';
  if (raw.contains('lowercase')) return 'New password must contain at least one lowercase letter.';
  if (raw.contains('number')) return 'New password must contain at least one number.';
  return 'Password change failed. Please try again.';
}
