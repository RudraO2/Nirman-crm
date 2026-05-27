import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/auth_repository.dart';

part 'auth_providers.g.dart';

/// Watches Supabase auth state changes.
/// UI layers use this to react to sign-in / sign-out events.
@riverpod
Stream<AuthState> authStateChanges(AuthStateChangesRef ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
}

/// Exposes the current Supabase session (null = unauthenticated).
@riverpod
Session? currentSession(CurrentSessionRef ref) {
  // Re-evaluate when auth state changes.
  ref.watch(authStateChangesProvider);
  return Supabase.instance.client.auth.currentSession;
}
