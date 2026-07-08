// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alarm_permissions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$alarmPermissionsHash() => r'257ef4a41d28f8ee3ce35426b70387d93cb1ff3e';

/// See also [alarmPermissions].
@ProviderFor(alarmPermissions)
final alarmPermissionsProvider = AutoDisposeProvider<AlarmPermissions>.internal(
  alarmPermissions,
  name: r'alarmPermissionsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$alarmPermissionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AlarmPermissionsRef = AutoDisposeProviderRef<AlarmPermissions>;
String _$alarmPermissionStatusHash() =>
    r'89d02a62a63b25aa4e5b375e0673d7f7f673a5d2';

/// Current permission snapshot for the warning banner. Invalidated after a
/// grant request so the banner refreshes.
///
/// Copied from [alarmPermissionStatus].
@ProviderFor(alarmPermissionStatus)
final alarmPermissionStatusProvider =
    AutoDisposeFutureProvider<AlarmPermissionStatus>.internal(
      alarmPermissionStatus,
      name: r'alarmPermissionStatusProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$alarmPermissionStatusHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AlarmPermissionStatusRef =
    AutoDisposeFutureProviderRef<AlarmPermissionStatus>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
