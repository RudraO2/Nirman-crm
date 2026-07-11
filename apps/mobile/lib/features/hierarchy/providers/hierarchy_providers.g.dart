// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hierarchy_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$hierarchyUsersHash() => r'01e7bd775e3119a74e8842a33044c21075c363b0';

/// Active tenant users for the Organization list. Invalidate after an edit.
///
/// Copied from [hierarchyUsers].
@ProviderFor(hierarchyUsers)
final hierarchyUsersProvider =
    AutoDisposeFutureProvider<List<HierarchyUser>>.internal(
      hierarchyUsers,
      name: r'hierarchyUsersProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$hierarchyUsersHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HierarchyUsersRef = AutoDisposeFutureProviderRef<List<HierarchyUser>>;
String _$agenciesHash() => r'1f4d0a8e81d4883cd3630ef0dc0d0daf14c2bec4';

/// Tenant partner agencies. Invalidate after creating one.
///
/// Copied from [agencies].
@ProviderFor(agencies)
final agenciesProvider = AutoDisposeFutureProvider<List<Agency>>.internal(
  agencies,
  name: r'agenciesProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$agenciesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AgenciesRef = AutoDisposeFutureProviderRef<List<Agency>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
