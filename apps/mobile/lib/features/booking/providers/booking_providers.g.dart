// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$activeHoldsHash() => r'b291d7cb15dea5c2bc67054d9307438bf0913dcd';

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

/// Active holds in the caller's scope, optionally filtered to [projectId]
/// (empty string / null = all projects). Family key is the project id or ''.
///
/// Copied from [activeHolds].
@ProviderFor(activeHolds)
const activeHoldsProvider = ActiveHoldsFamily();

/// Active holds in the caller's scope, optionally filtered to [projectId]
/// (empty string / null = all projects). Family key is the project id or ''.
///
/// Copied from [activeHolds].
class ActiveHoldsFamily extends Family<AsyncValue<List<ActiveHold>>> {
  /// Active holds in the caller's scope, optionally filtered to [projectId]
  /// (empty string / null = all projects). Family key is the project id or ''.
  ///
  /// Copied from [activeHolds].
  const ActiveHoldsFamily();

  /// Active holds in the caller's scope, optionally filtered to [projectId]
  /// (empty string / null = all projects). Family key is the project id or ''.
  ///
  /// Copied from [activeHolds].
  ActiveHoldsProvider call(String projectId) {
    return ActiveHoldsProvider(projectId);
  }

  @override
  ActiveHoldsProvider getProviderOverride(
    covariant ActiveHoldsProvider provider,
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
  String? get name => r'activeHoldsProvider';
}

/// Active holds in the caller's scope, optionally filtered to [projectId]
/// (empty string / null = all projects). Family key is the project id or ''.
///
/// Copied from [activeHolds].
class ActiveHoldsProvider extends AutoDisposeFutureProvider<List<ActiveHold>> {
  /// Active holds in the caller's scope, optionally filtered to [projectId]
  /// (empty string / null = all projects). Family key is the project id or ''.
  ///
  /// Copied from [activeHolds].
  ActiveHoldsProvider(String projectId)
    : this._internal(
        (ref) => activeHolds(ref as ActiveHoldsRef, projectId),
        from: activeHoldsProvider,
        name: r'activeHoldsProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$activeHoldsHash,
        dependencies: ActiveHoldsFamily._dependencies,
        allTransitiveDependencies: ActiveHoldsFamily._allTransitiveDependencies,
        projectId: projectId,
      );

  ActiveHoldsProvider._internal(
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
    FutureOr<List<ActiveHold>> Function(ActiveHoldsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ActiveHoldsProvider._internal(
        (ref) => create(ref as ActiveHoldsRef),
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
  AutoDisposeFutureProviderElement<List<ActiveHold>> createElement() {
    return _ActiveHoldsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ActiveHoldsProvider && other.projectId == projectId;
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
mixin ActiveHoldsRef on AutoDisposeFutureProviderRef<List<ActiveHold>> {
  /// The parameter `projectId` of this provider.
  String get projectId;
}

class _ActiveHoldsProviderElement
    extends AutoDisposeFutureProviderElement<List<ActiveHold>>
    with ActiveHoldsRef {
  _ActiveHoldsProviderElement(super.provider);

  @override
  String get projectId => (origin as ActiveHoldsProvider).projectId;
}

String _$bookingStatsHash() => r'ce8df0cbb82cd4aa2505f43ae55dda176782c5ae';

/// Booking stats for the caller's scope, optionally filtered to [projectId] and
/// [agentId] (empty string = no filter). Family key is (projectId, agentId).
///
/// Copied from [bookingStats].
@ProviderFor(bookingStats)
const bookingStatsProvider = BookingStatsFamily();

/// Booking stats for the caller's scope, optionally filtered to [projectId] and
/// [agentId] (empty string = no filter). Family key is (projectId, agentId).
///
/// Copied from [bookingStats].
class BookingStatsFamily extends Family<AsyncValue<BookingStats>> {
  /// Booking stats for the caller's scope, optionally filtered to [projectId] and
  /// [agentId] (empty string = no filter). Family key is (projectId, agentId).
  ///
  /// Copied from [bookingStats].
  const BookingStatsFamily();

  /// Booking stats for the caller's scope, optionally filtered to [projectId] and
  /// [agentId] (empty string = no filter). Family key is (projectId, agentId).
  ///
  /// Copied from [bookingStats].
  BookingStatsProvider call(String projectId, String agentId) {
    return BookingStatsProvider(projectId, agentId);
  }

  @override
  BookingStatsProvider getProviderOverride(
    covariant BookingStatsProvider provider,
  ) {
    return call(provider.projectId, provider.agentId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'bookingStatsProvider';
}

/// Booking stats for the caller's scope, optionally filtered to [projectId] and
/// [agentId] (empty string = no filter). Family key is (projectId, agentId).
///
/// Copied from [bookingStats].
class BookingStatsProvider extends AutoDisposeFutureProvider<BookingStats> {
  /// Booking stats for the caller's scope, optionally filtered to [projectId] and
  /// [agentId] (empty string = no filter). Family key is (projectId, agentId).
  ///
  /// Copied from [bookingStats].
  BookingStatsProvider(String projectId, String agentId)
    : this._internal(
        (ref) => bookingStats(ref as BookingStatsRef, projectId, agentId),
        from: bookingStatsProvider,
        name: r'bookingStatsProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$bookingStatsHash,
        dependencies: BookingStatsFamily._dependencies,
        allTransitiveDependencies:
            BookingStatsFamily._allTransitiveDependencies,
        projectId: projectId,
        agentId: agentId,
      );

  BookingStatsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.projectId,
    required this.agentId,
  }) : super.internal();

  final String projectId;
  final String agentId;

  @override
  Override overrideWith(
    FutureOr<BookingStats> Function(BookingStatsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: BookingStatsProvider._internal(
        (ref) => create(ref as BookingStatsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        projectId: projectId,
        agentId: agentId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<BookingStats> createElement() {
    return _BookingStatsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is BookingStatsProvider &&
        other.projectId == projectId &&
        other.agentId == agentId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, projectId.hashCode);
    hash = _SystemHash.combine(hash, agentId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin BookingStatsRef on AutoDisposeFutureProviderRef<BookingStats> {
  /// The parameter `projectId` of this provider.
  String get projectId;

  /// The parameter `agentId` of this provider.
  String get agentId;
}

class _BookingStatsProviderElement
    extends AutoDisposeFutureProviderElement<BookingStats>
    with BookingStatsRef {
  _BookingStatsProviderElement(super.provider);

  @override
  String get projectId => (origin as BookingStatsProvider).projectId;
  @override
  String get agentId => (origin as BookingStatsProvider).agentId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
