// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alarm_scheduler.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$alarmSchedulerHash() => r'4aa59091abae7e00bb2bc87aead811059996ec5b';

/// Android → real scheduler; everything else → logged no-op (iOS deferred).
///
/// Copied from [alarmScheduler].
@ProviderFor(alarmScheduler)
final alarmSchedulerProvider = AutoDisposeProvider<AlarmScheduler>.internal(
  alarmScheduler,
  name: r'alarmSchedulerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$alarmSchedulerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AlarmSchedulerRef = AutoDisposeProviderRef<AlarmScheduler>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
