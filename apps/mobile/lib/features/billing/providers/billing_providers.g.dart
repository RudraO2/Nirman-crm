// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'billing_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$pausedStateHash() => r'b9c964db6b5488d0bd02f304d0ea0b89c7ad42bb';

/// Resolves whether the current tenant is locked out, and which screen to show.
///
/// SECURITY NOTE (AC #1): this is a *display* decision only. Access is enforced
/// server-side by `auth_tenant_id()` (0056); if this provider is wrong or errors,
/// the worst case is a suspended user briefly sees an empty app shell whose data
/// RPCs all still fail-closed at Postgres. It therefore fails OPEN on the display
/// (treats ambiguous/network errors as "not paused" → normal retry, AC #7) rather
/// than risk locking out a paying, active customer over a transient blip.
///
/// Copied from [pausedState].
@ProviderFor(pausedState)
final pausedStateProvider = AutoDisposeFutureProvider<PausedState>.internal(
  pausedState,
  name: r'pausedStateProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$pausedStateHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PausedStateRef = AutoDisposeFutureProviderRef<PausedState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
