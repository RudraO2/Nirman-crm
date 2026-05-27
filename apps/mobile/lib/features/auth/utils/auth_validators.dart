// Shared auth validation utilities.
// Used by LoginScreen, PasswordChangeScreen, AuthRepository, and unit tests.
// Single source of truth — eliminates shadow copies in tests.

/// FlutterSecureStorage key for the must_change_password flag.
/// Use this function in ALL three locations:
///   login_screen.dart   — write on login when mustChangePassword=true
///   app_router.dart     — read in redirect guard
///   auth_repository.dart — delete after successful changePassword
String mustChangePasswordKey(String userId) => 'must_change_password_$userId';

/// Maps a raw login exception message to a user-visible string.
String mapLoginError(String raw) {
  if (raw.toLowerCase().contains('deactivated')) {
    return 'Your account has been deactivated. Contact your admin.';
  }
  if (raw.toLowerCase().contains('not authorised')) {
    return 'This account is not authorised for this platform.';
  }
  return 'Invalid username or password.';
}

/// Validates a new password against complexity rules.
/// Mirrors the Edge Function Zod schema — keep in sync with change-password/index.ts.
/// Returns an error message, or null if all checks pass.
String? validateNewPassword({required String newPassword, required String confirm}) {
  if (newPassword.length < 8) return 'New password must be at least 8 characters';
  if (!newPassword.contains(RegExp(r'[A-Z]'))) {
    return 'New password must contain at least one uppercase letter';
  }
  if (!newPassword.contains(RegExp(r'[a-z]'))) {
    return 'New password must contain at least one lowercase letter';
  }
  if (!newPassword.contains(RegExp(r'[0-9]'))) {
    return 'New password must contain at least one number';
  }
  if (newPassword != confirm) return 'Passwords do not match';
  return null;
}

/// Maps a raw change-password exception message to a user-visible string.
String mapChangeError(String raw) {
  if (raw.contains('Current password is incorrect')) return 'Current password is incorrect.';
  if (raw.contains('differ')) return 'New password must differ from your current password.';
  if (raw.contains('at least 8')) return 'New password must be at least 8 characters.';
  if (raw.contains('uppercase')) return 'New password must contain at least one uppercase letter.';
  if (raw.contains('lowercase')) return 'New password must contain at least one lowercase letter.';
  if (raw.contains('number')) return 'New password must contain at least one number.';
  return 'Password change failed. Please try again.';
}
