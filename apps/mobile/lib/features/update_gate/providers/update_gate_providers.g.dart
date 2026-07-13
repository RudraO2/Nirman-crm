// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_gate_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$updateRequiredHash() => r'af129d13670884bad804352a70295d6e9fb4b56e';

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
///
/// Copied from [updateRequired].
@ProviderFor(updateRequired)
final updateRequiredProvider = AutoDisposeFutureProvider<bool>.internal(
  updateRequired,
  name: r'updateRequiredProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$updateRequiredHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UpdateRequiredRef = AutoDisposeFutureProviderRef<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
