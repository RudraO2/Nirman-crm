import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'auth_repository.g.dart';

/// Handles authentication via the custom `login` Edge Function.
/// All login goes through the Edge Function (not supabase_flutter direct auth)
/// so that platform segregation (FR-30) is enforced server-side before any JWT issues.
class AuthRepository {
  final SupabaseClient _supabase;

  const AuthRepository(this._supabase);

  /// Calls the `login` Edge Function with platform="mobile".
  /// On success, initialises the Supabase session from the returned tokens.
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
      final body = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final err = body['error'] is Map
          ? Map<String, dynamic>.from(body['error'] as Map)
          : <String, dynamic>{};
      final errMsg = err['message'] as String? ?? 'Login failed';
      throw AuthException(errMsg, statusCode: response.status.toString());
    }

    final body = Map<String, dynamic>.from(response.data as Map);
    final payload = Map<String, dynamic>.from(body['data'] as Map);
    final refreshToken = payload['refresh_token'] as String;

    // setSession() exchanges refresh token for fresh access token + user.
    // Persists session via GoTrueClient (auto-refresh enabled).
    await _supabase.auth.setSession(refreshToken);

    return (
      role: payload['role'] as String,
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
      final body = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final err = body['error'] is Map
          ? Map<String, dynamic>.from(body['error'] as Map)
          : <String, dynamic>{};
      final msg = err['message'] as String? ?? 'Password change failed';
      throw AuthException(msg, statusCode: response.status.toString());
    }

    final body = Map<String, dynamic>.from(response.data as Map);
    final payload = Map<String, dynamic>.from(body['data'] as Map);
    final refreshToken = payload['refresh_token'] as String;

    // Replace session with new tokens (carries must_change_password=false in app_metadata)
    await _supabase.auth.setSession(refreshToken);

    // Clear forced-change flag from secure storage
    final userId = _supabase.auth.currentSession?.user.id;
    if (userId != null) {
      const storage = FlutterSecureStorage();
      await storage.delete(key: 'must_change_password_$userId');
    }
  }

  Future<void> signOut() async {
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
