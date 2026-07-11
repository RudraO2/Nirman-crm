// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'team_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$teamLeadsHash() => r'77174721af9dc44da4645b949a9c1b9d1fccfdcd';

/// Leads in the caller's visibility scope. Invalidate to refetch.
///
/// Copied from [teamLeads].
@ProviderFor(teamLeads)
final teamLeadsProvider = AutoDisposeFutureProvider<List<TeamLead>>.internal(
  teamLeads,
  name: r'teamLeadsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$teamLeadsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TeamLeadsRef = AutoDisposeFutureProviderRef<List<TeamLead>>;
String _$ownerNamesHash() => r'522c536e70d432d7e475b2ca3128198b82b6a53f';

/// id→display-name for ONLY the owners appearing in [teamLeads]. Empty map on
/// error (owner chip falls back to a masked label).
///
/// Copied from [ownerNames].
@ProviderFor(ownerNames)
final ownerNamesProvider =
    AutoDisposeFutureProvider<Map<String, String>>.internal(
      ownerNames,
      name: r'ownerNamesProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$ownerNamesHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef OwnerNamesRef = AutoDisposeFutureProviderRef<Map<String, String>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
