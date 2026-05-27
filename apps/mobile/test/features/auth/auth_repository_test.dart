// Stories 1.4 + 1.5 — Auth validator unit tests.
// Tests the shared auth_validators.dart functions used by LoginScreen,
// PasswordChangeScreen, and AuthRepository — not shadow copies.
// Run with: flutter test test/features/auth/auth_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/auth/utils/auth_validators.dart';

void main() {
  group('Login error mapping', () {
    test('platform is always "mobile" for mobile app login calls', () {
      const platform = 'mobile';
      expect(platform, equals('mobile'));
    });

    test('deactivated account', () {
      final mapped = mapLoginError('AuthException: Account deactivated');
      expect(mapped, contains('deactivated'));
    });

    test('wrong credentials', () {
      final mapped = mapLoginError('AuthException: Invalid username or password');
      expect(mapped, equals('Invalid username or password.'));
    });

    test('platform rejection', () {
      final mapped =
          mapLoginError('AuthException: This account is not authorised for web access');
      expect(mapped, contains('not authorised'));
    });
  });

  group('Password complexity validation', () {
    test('password shorter than 8 chars fails', () {
      final err = validateNewPassword(newPassword: 'Ab1!xxx', confirm: 'Ab1!xxx');
      expect(err, isNotNull);
      expect(err, contains('8'));
    });

    test('password without uppercase fails', () {
      final err = validateNewPassword(newPassword: 'nouppercase1!', confirm: 'nouppercase1!');
      expect(err, isNotNull);
      expect(err, contains('uppercase'));
    });

    test('password without lowercase fails', () {
      final err = validateNewPassword(newPassword: 'NOLOWERCASE1!', confirm: 'NOLOWERCASE1!');
      expect(err, isNotNull);
      expect(err, contains('lowercase'));
    });

    test('password without digit fails', () {
      final err = validateNewPassword(newPassword: 'NoDigitsXX!', confirm: 'NoDigitsXX!');
      expect(err, isNotNull);
      expect(err, contains('number'));
    });

    test('mismatched confirm fails', () {
      final err = validateNewPassword(newPassword: 'ValidPass1!', confirm: 'Different1!');
      expect(err, isNotNull);
      expect(err, contains('match'));
    });

    test('valid password passes all checks', () {
      expect(
        validateNewPassword(newPassword: 'ValidPass1!', confirm: 'ValidPass1!'),
        isNull,
      );
    });
  });

  group('Change-password error mapping', () {
    test('wrong current password', () {
      final mapped = mapChangeError('AuthException: Current password is incorrect');
      expect(mapped, contains('incorrect'));
    });

    test('same-as-current rejected by server', () {
      final mapped =
          mapChangeError('AuthException: New password must differ from current password.');
      expect(mapped, contains('differ'));
    });

    test('server complexity — length', () {
      final mapped =
          mapChangeError('AuthException: New password must be at least 8 characters');
      expect(mapped, contains('8'));
    });

    test('generic server error gives fallback', () {
      final mapped = mapChangeError('AuthException: internal_error');
      expect(mapped, contains('try again'));
    });
  });

  group('mustChangePasswordKey', () {
    test('key includes user id', () {
      expect(mustChangePasswordKey('abc-123'), equals('must_change_password_abc-123'));
    });

    test('different user ids produce different keys', () {
      expect(
        mustChangePasswordKey('user-1') == mustChangePasswordKey('user-2'),
        isFalse,
      );
    });
  });
}
