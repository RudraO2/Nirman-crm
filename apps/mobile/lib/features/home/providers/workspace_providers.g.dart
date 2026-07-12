// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$tenantUsesInventoryHash() =>
    r'4bf4eef4fa43ac31e71db1a0e7873c20ae1b9735';

/// True once the caller's tenant has ever created a project (one-way, server-truth).
///
/// Copied from [tenantUsesInventory].
@ProviderFor(tenantUsesInventory)
final tenantUsesInventoryProvider = FutureProvider<bool>.internal(
  tenantUsesInventory,
  name: r'tenantUsesInventoryProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$tenantUsesInventoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TenantUsesInventoryRef = FutureProviderRef<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
