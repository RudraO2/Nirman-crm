import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/screen_security_service.dart';
import '../utils/auth_validators.dart';

part 'auth_repository.g.dart';

/// Handles authentication via the custom `login` Edge Function.
/// All login goes through the Edge Function (not supabase_flutter direct auth)
/// so that platform segregation (FR-30) is enforced server-side before any JWT issues.
class AuthRepository {
  final SupabaseClient _supabase;

  const AuthRepository(this._supabase);

  /// Decodes the `exp` claim from a JWT access token without external libraries.
  /// Returns the expiry as epoch seconds, or null if decoding fails.
  static int? _jwtExpiry(String accessToken) {
    try {
      final parts = accessToken.split('.');
      if (parts.length != 3) return null;
      String payload = parts[1];
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      return json['exp'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// Builds a recoverSession JSON string using the actual token expiry.
  /// Uses server-supplied expiresAt when available, falls back to JWT exp claim.
  static String _sessionJson(
    String accessToken,
    String refreshToken, {
    int? expiresAt,
  }) {
    final expAt = expiresAt ??
        _jwtExpiry(accessToken) ??
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600);
    final expIn = expAt - (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final safeExpIn = expIn > 60 ? expIn : 3600;
    return '{"access_token":"$accessToken","refresh_token":"$refreshToken"'
        ',"token_type":"bearer","expires_in":$safeExpIn,"expires_at":$expAt}';
  }

  /// Calls the `login` Edge Function with platform="mobile".
  /// On success, initialises the Supabase session from the returned tokens
  /// and applies screen security based on role (Story 1.8 — FR-31).
  /// Throws [AuthException] on 401/403, [Exception] on network/5xx.
  Future<({String role, bool mustChangePassword})> login({
    required String username,
    required String password,
  }) async {
    final response = await _supabase.functions.invoke(
      'login',
      body: {
        'username': username.trim().toLowerCase(),
        'password': password,
        'platform': 'mobile',
      },
    );

    if (response.status != 200) {
      final errMsg =
          (response.data as Map<String, dynamic>?)?['error']?['message']
              as String? ??
          'Login failed';
      throw AuthException(errMsg, statusCode: response.status.toString());
    }

    final payload = (response.data as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
    final accessToken = payload['access_token'] as String;
    final refreshToken = payload['refresh_token'] as String;
    final role = payload['role'] as String;

    try {
      await _supabase.auth.recoverSession(
        _sessionJson(accessToken, refreshToken),
      );
    } catch (e) {
      throw AuthException(
        'Session initialisation failed. Please log in again.',
        statusCode: '500',
      );
    }

    // Story 1.8: apply FLAG_SECURE (Android) / blur (iOS) immediately after login
    await ScreenSecurityService.applyForRole(role);

    return (
      role: role,
      mustChangePassword: payload['must_change_password'] as bool,
    );
  }

  /// Calls the `change-password` Edge Function.
  /// Verifies [currentPassword] against public.users bcrypt hash server-side.
  /// On success, replaces Supabase session with new tokens and clears the
  /// must_change_password flag from secure storage.
  ///
  /// Throws [AuthException] on 400 (wrong password / complexity) or 401.
  /// Throws [Exception] on network/5xx.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _supabase.functions.invoke(
      'change-password',
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );

    if (response.status != 200) {
      final msg =
          (response.data as Map<String, dynamic>?)?['error']?['message']
              as String? ??
          'Password change failed';
      throw AuthException(msg, statusCode: response.status.toString());
    }

    final payload = (response.data as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
    final accessToken = payload['access_token'] as String;
    final refreshToken = payload['refresh_token'] as String;
    final expiresAt = payload['expires_at'] as int?;

    try {
      await _supabase.auth.recoverSession(
        _sessionJson(accessToken, refreshToken, expiresAt: expiresAt),
      );
    } catch (e) {
      throw AuthException(
        'Password changed but session refresh failed. Please log in again.',
        statusCode: '500',
      );
    }

    final userId = _supabase.auth.currentSession?.user.id;
    if (userId != null) {
      const storage = FlutterSecureStorage();
      await storage.delete(key: mustChangePasswordKey(userId));
    } else {
      debugPrint('[AuthRepository] userId null after changePassword recoverSession; '
          'relying on JWT claim for router guard update.');
    }
  }

  /// Signs out the current user and clears screen security protection.
  /// 2-second timeout on disable() guards against MethodChannel hang.
  Future<void> signOut() async {
    await ScreenSecurityService.disable().timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    await _supabase.auth.signOut();
  }

  Session? get currentSession => _supabase.auth.currentSession;

  Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;
}

@riverpod
AuthRepository authRepository(AuthRepositoryRef ref) {
  return AuthRepository(Supabase.instance.client);
}
