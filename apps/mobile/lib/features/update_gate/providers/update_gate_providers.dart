import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/providers/auth_providers.dart';

part 'update_gate_providers.g.dart';

/// Force-update gate (migration 0119).
///
/// Compares this install's Android build number (the `+N` in pubspec `version:`)
/// against `get_min_app_build()` — an anon-callable platform config RPC, so the
/// check works on the login screen before any session exists.
///
/// FAIL-OPEN by design: any error (network, RPC missing on an old backend,
/// unparseable build number) resolves to "no update required". This gate is an
/// operator convenience for retiring broken old APKs — never a way to brick the
/// app on a bad connection. Mirrors the 9.6 billing gate philosophy.
@riverpod
Future<bool> updateRequired(UpdateRequiredRef ref) async {
  // Re-evaluate on auth events (TOKEN_REFRESHED fires on app resume) so a
  // long-lived session picks up a raised min_build without a cold start.
  ref.watch(authStateChangesProvider);

  try {
    final info = await PackageInfo.fromPlatform();
    final current = int.tryParse(info.buildNumber) ?? 0;
    if (current == 0) return false; // own build unreadable → fail open

    final result = await Supabase.instance.client
        .rpc('get_min_app_build', params: {'p_platform': 'android'});
    final minBuild = (result as num?)?.toInt() ?? 0;
    return current < minBuild;
  } catch (_) {
    return false; // network / RPC error → fail open
  }
}
