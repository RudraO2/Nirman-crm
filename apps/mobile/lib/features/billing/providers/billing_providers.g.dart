// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'billing_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$billingGateHash() => r'd598f211cf3027aa0e716fd6f56057e0ca394c1b';

/// Resolves the current tenant's access state from its billing status.
///
/// SECURITY (AC #1): display decision only. Access is enforced server-side — the
/// `auth_tenant_id()` chokepoint (0056) plus migration 0092 (which closed the last
/// un-gated read, `get_my_leads`) mean a suspended tenant has NO reachable data on
/// any RPC. So this provider FAILS OPEN on read/network error (returns `ok` → normal
/// app) rather than risk locking out a paying customer over a transient blip; the
/// server stays the gate regardless.
///
/// `get_my_billing_status()` is now readable by any tenant member (0092), so both
/// admins and employees resolve reliably — no fragile data-RPC probe.
///
/// Copied from [billingGate].
@ProviderFor(billingGate)
final billingGateProvider = AutoDisposeFutureProvider<BillingGate>.internal(
  billingGate,
  name: r'billingGateProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$billingGateHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BillingGateRef = AutoDisposeFutureProviderRef<BillingGate>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
