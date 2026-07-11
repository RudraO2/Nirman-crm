// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$projectUnitsHash() => r'f1c31aa34f3bff7fffb9eb3554be986f1965b30b';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// Units for [projectId] via get_project_units. Invalidate to refetch (the grid
/// screen does this on Realtime `units` changes).
///
/// Copied from [projectUnits].
@ProviderFor(projectUnits)
const projectUnitsProvider = ProjectUnitsFamily();

/// Units for [projectId] via get_project_units. Invalidate to refetch (the grid
/// screen does this on Realtime `units` changes).
///
/// Copied from [projectUnits].
class ProjectUnitsFamily extends Family<AsyncValue<List<ProjectUnit>>> {
  /// Units for [projectId] via get_project_units. Invalidate to refetch (the grid
  /// screen does this on Realtime `units` changes).
  ///
  /// Copied from [projectUnits].
  const ProjectUnitsFamily();

  /// Units for [projectId] via get_project_units. Invalidate to refetch (the grid
  /// screen does this on Realtime `units` changes).
  ///
  /// Copied from [projectUnits].
  ProjectUnitsProvider call(String projectId) {
    return ProjectUnitsProvider(projectId);
  }

  @override
  ProjectUnitsProvider getProviderOverride(
    covariant ProjectUnitsProvider provider,
  ) {
    return call(provider.projectId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'projectUnitsProvider';
}

/// Units for [projectId] via get_project_units. Invalidate to refetch (the grid
/// screen does this on Realtime `units` changes).
///
/// Copied from [projectUnits].
class ProjectUnitsProvider
    extends AutoDisposeFutureProvider<List<ProjectUnit>> {
  /// Units for [projectId] via get_project_units. Invalidate to refetch (the grid
  /// screen does this on Realtime `units` changes).
  ///
  /// Copied from [projectUnits].
  ProjectUnitsProvider(String projectId)
    : this._internal(
        (ref) => projectUnits(ref as ProjectUnitsRef, projectId),
        from: projectUnitsProvider,
        name: r'projectUnitsProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$projectUnitsHash,
        dependencies: ProjectUnitsFamily._dependencies,
        allTransitiveDependencies:
            ProjectUnitsFamily._allTransitiveDependencies,
        projectId: projectId,
      );

  ProjectUnitsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.projectId,
  }) : super.internal();

  final String projectId;

  @override
  Override overrideWith(
    FutureOr<List<ProjectUnit>> Function(ProjectUnitsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ProjectUnitsProvider._internal(
        (ref) => create(ref as ProjectUnitsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        projectId: projectId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<ProjectUnit>> createElement() {
    return _ProjectUnitsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectUnitsProvider && other.projectId == projectId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, projectId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ProjectUnitsRef on AutoDisposeFutureProviderRef<List<ProjectUnit>> {
  /// The parameter `projectId` of this provider.
  String get projectId;
}

class _ProjectUnitsProviderElement
    extends AutoDisposeFutureProviderElement<List<ProjectUnit>>
    with ProjectUnitsRef {
  _ProjectUnitsProviderElement(super.provider);

  @override
  String get projectId => (origin as ProjectUnitsProvider).projectId;
}

String _$activeHoldHash() => r'7cc2ded8fc95b232688d2cb7e1f8198a0aee7c53';

/// Story 15.2 — the active hold on [unitId] (null if none). Drives the countdown on
/// a held unit's detail sheet. Invalidate after placing a hold.
///
/// Copied from [activeHold].
@ProviderFor(activeHold)
const activeHoldProvider = ActiveHoldFamily();

/// Story 15.2 — the active hold on [unitId] (null if none). Drives the countdown on
/// a held unit's detail sheet. Invalidate after placing a hold.
///
/// Copied from [activeHold].
class ActiveHoldFamily extends Family<AsyncValue<UnitHold?>> {
  /// Story 15.2 — the active hold on [unitId] (null if none). Drives the countdown on
  /// a held unit's detail sheet. Invalidate after placing a hold.
  ///
  /// Copied from [activeHold].
  const ActiveHoldFamily();

  /// Story 15.2 — the active hold on [unitId] (null if none). Drives the countdown on
  /// a held unit's detail sheet. Invalidate after placing a hold.
  ///
  /// Copied from [activeHold].
  ActiveHoldProvider call(String unitId) {
    return ActiveHoldProvider(unitId);
  }

  @override
  ActiveHoldProvider getProviderOverride(
    covariant ActiveHoldProvider provider,
  ) {
    return call(provider.unitId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'activeHoldProvider';
}

/// Story 15.2 — the active hold on [unitId] (null if none). Drives the countdown on
/// a held unit's detail sheet. Invalidate after placing a hold.
///
/// Copied from [activeHold].
class ActiveHoldProvider extends AutoDisposeFutureProvider<UnitHold?> {
  /// Story 15.2 — the active hold on [unitId] (null if none). Drives the countdown on
  /// a held unit's detail sheet. Invalidate after placing a hold.
  ///
  /// Copied from [activeHold].
  ActiveHoldProvider(String unitId)
    : this._internal(
        (ref) => activeHold(ref as ActiveHoldRef, unitId),
        from: activeHoldProvider,
        name: r'activeHoldProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$activeHoldHash,
        dependencies: ActiveHoldFamily._dependencies,
        allTransitiveDependencies: ActiveHoldFamily._allTransitiveDependencies,
        unitId: unitId,
      );

  ActiveHoldProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.unitId,
  }) : super.internal();

  final String unitId;

  @override
  Override overrideWith(
    FutureOr<UnitHold?> Function(ActiveHoldRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ActiveHoldProvider._internal(
        (ref) => create(ref as ActiveHoldRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        unitId: unitId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<UnitHold?> createElement() {
    return _ActiveHoldProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ActiveHoldProvider && other.unitId == unitId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, unitId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ActiveHoldRef on AutoDisposeFutureProviderRef<UnitHold?> {
  /// The parameter `unitId` of this provider.
  String get unitId;
}

class _ActiveHoldProviderElement
    extends AutoDisposeFutureProviderElement<UnitHold?>
    with ActiveHoldRef {
  _ActiveHoldProviderElement(super.provider);

  @override
  String get unitId => (origin as ActiveHoldProvider).unitId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
