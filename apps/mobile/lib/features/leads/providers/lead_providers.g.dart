// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lead_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$leadByIdHash() => r'312bcd5bcbfcb102a4c8ca3da30ca34e81a64cd5';

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

/// Single lead by ID with PII decrypted + project_ids (Story 2.4).
/// Returns null if not found / not owned by caller.
///
/// Copied from [leadById].
@ProviderFor(leadById)
const leadByIdProvider = LeadByIdFamily();

/// Single lead by ID with PII decrypted + project_ids (Story 2.4).
/// Returns null if not found / not owned by caller.
///
/// Copied from [leadById].
class LeadByIdFamily extends Family<AsyncValue<LeadDetail?>> {
  /// Single lead by ID with PII decrypted + project_ids (Story 2.4).
  /// Returns null if not found / not owned by caller.
  ///
  /// Copied from [leadById].
  const LeadByIdFamily();

  /// Single lead by ID with PII decrypted + project_ids (Story 2.4).
  /// Returns null if not found / not owned by caller.
  ///
  /// Copied from [leadById].
  LeadByIdProvider call(String id) {
    return LeadByIdProvider(id);
  }

  @override
  LeadByIdProvider getProviderOverride(covariant LeadByIdProvider provider) {
    return call(provider.id);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'leadByIdProvider';
}

/// Single lead by ID with PII decrypted + project_ids (Story 2.4).
/// Returns null if not found / not owned by caller.
///
/// Copied from [leadById].
class LeadByIdProvider extends AutoDisposeFutureProvider<LeadDetail?> {
  /// Single lead by ID with PII decrypted + project_ids (Story 2.4).
  /// Returns null if not found / not owned by caller.
  ///
  /// Copied from [leadById].
  LeadByIdProvider(String id)
    : this._internal(
        (ref) => leadById(ref as LeadByIdRef, id),
        from: leadByIdProvider,
        name: r'leadByIdProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$leadByIdHash,
        dependencies: LeadByIdFamily._dependencies,
        allTransitiveDependencies: LeadByIdFamily._allTransitiveDependencies,
        id: id,
      );

  LeadByIdProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.id,
  }) : super.internal();

  final String id;

  @override
  Override overrideWith(
    FutureOr<LeadDetail?> Function(LeadByIdRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: LeadByIdProvider._internal(
        (ref) => create(ref as LeadByIdRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        id: id,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<LeadDetail?> createElement() {
    return _LeadByIdProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is LeadByIdProvider && other.id == id;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, id.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin LeadByIdRef on AutoDisposeFutureProviderRef<LeadDetail?> {
  /// The parameter `id` of this provider.
  String get id;
}

class _LeadByIdProviderElement
    extends AutoDisposeFutureProviderElement<LeadDetail?>
    with LeadByIdRef {
  _LeadByIdProviderElement(super.provider);

  @override
  String get id => (origin as LeadByIdProvider).id;
}

String _$myLeadsHash() => r'd36ff7405f6666946e8a5a16836dfcb7585f63c8';

/// Urgency-sorted active leads for the current user (Story 2.5).
/// Invalidate this provider after any lead mutation to refresh the list.
///
/// Copied from [myLeads].
@ProviderFor(myLeads)
final myLeadsProvider = AutoDisposeFutureProvider<List<LeadListItem>>.internal(
  myLeads,
  name: r'myLeadsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$myLeadsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MyLeadsRef = AutoDisposeFutureProviderRef<List<LeadListItem>>;
String _$availableProjectsHash() => r'148826f84fa8e9eb0f8e341d25b5058e4f321fbd';

/// Available projects for the lead form project picker.
///
/// Copied from [availableProjects].
@ProviderFor(availableProjects)
final availableProjectsProvider =
    AutoDisposeFutureProvider<List<ProjectRef>>.internal(
      availableProjects,
      name: r'availableProjectsProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$availableProjectsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AvailableProjectsRef = AutoDisposeFutureProviderRef<List<ProjectRef>>;
String _$leadTimelineHash() => r'eb88d1ad7c2779ed88fb902057216b6c68223ed5';

/// Timeline events for a lead (FR-19).
///
/// Copied from [leadTimeline].
@ProviderFor(leadTimeline)
const leadTimelineProvider = LeadTimelineFamily();

/// Timeline events for a lead (FR-19).
///
/// Copied from [leadTimeline].
class LeadTimelineFamily extends Family<AsyncValue<List<TimelineEntry>>> {
  /// Timeline events for a lead (FR-19).
  ///
  /// Copied from [leadTimeline].
  const LeadTimelineFamily();

  /// Timeline events for a lead (FR-19).
  ///
  /// Copied from [leadTimeline].
  LeadTimelineProvider call(String id) {
    return LeadTimelineProvider(id);
  }

  @override
  LeadTimelineProvider getProviderOverride(
    covariant LeadTimelineProvider provider,
  ) {
    return call(provider.id);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'leadTimelineProvider';
}

/// Timeline events for a lead (FR-19).
///
/// Copied from [leadTimeline].
class LeadTimelineProvider
    extends AutoDisposeFutureProvider<List<TimelineEntry>> {
  /// Timeline events for a lead (FR-19).
  ///
  /// Copied from [leadTimeline].
  LeadTimelineProvider(String id)
    : this._internal(
        (ref) => leadTimeline(ref as LeadTimelineRef, id),
        from: leadTimelineProvider,
        name: r'leadTimelineProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$leadTimelineHash,
        dependencies: LeadTimelineFamily._dependencies,
        allTransitiveDependencies:
            LeadTimelineFamily._allTransitiveDependencies,
        id: id,
      );

  LeadTimelineProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.id,
  }) : super.internal();

  final String id;

  @override
  Override overrideWith(
    FutureOr<List<TimelineEntry>> Function(LeadTimelineRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: LeadTimelineProvider._internal(
        (ref) => create(ref as LeadTimelineRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        id: id,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<TimelineEntry>> createElement() {
    return _LeadTimelineProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is LeadTimelineProvider && other.id == id;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, id.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin LeadTimelineRef on AutoDisposeFutureProviderRef<List<TimelineEntry>> {
  /// The parameter `id` of this provider.
  String get id;
}

class _LeadTimelineProviderElement
    extends AutoDisposeFutureProviderElement<List<TimelineEntry>>
    with LeadTimelineRef {
  _LeadTimelineProviderElement(super.provider);

  @override
  String get id => (origin as LeadTimelineProvider).id;
}

String _$archivedLeadsHash() => r'24713ca8b47ce7ce4da9c63725d12ffe97c68e43';

/// Caller's archived leads (dead/sold/future), filtered by [query] (Story 2.8).
/// Family keyed on query so debounced search updates the cache key cleanly.
///
/// Copied from [archivedLeads].
@ProviderFor(archivedLeads)
const archivedLeadsProvider = ArchivedLeadsFamily();

/// Caller's archived leads (dead/sold/future), filtered by [query] (Story 2.8).
/// Family keyed on query so debounced search updates the cache key cleanly.
///
/// Copied from [archivedLeads].
class ArchivedLeadsFamily extends Family<AsyncValue<List<LeadListItem>>> {
  /// Caller's archived leads (dead/sold/future), filtered by [query] (Story 2.8).
  /// Family keyed on query so debounced search updates the cache key cleanly.
  ///
  /// Copied from [archivedLeads].
  const ArchivedLeadsFamily();

  /// Caller's archived leads (dead/sold/future), filtered by [query] (Story 2.8).
  /// Family keyed on query so debounced search updates the cache key cleanly.
  ///
  /// Copied from [archivedLeads].
  ArchivedLeadsProvider call(String query) {
    return ArchivedLeadsProvider(query);
  }

  @override
  ArchivedLeadsProvider getProviderOverride(
    covariant ArchivedLeadsProvider provider,
  ) {
    return call(provider.query);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'archivedLeadsProvider';
}

/// Caller's archived leads (dead/sold/future), filtered by [query] (Story 2.8).
/// Family keyed on query so debounced search updates the cache key cleanly.
///
/// Copied from [archivedLeads].
class ArchivedLeadsProvider
    extends AutoDisposeFutureProvider<List<LeadListItem>> {
  /// Caller's archived leads (dead/sold/future), filtered by [query] (Story 2.8).
  /// Family keyed on query so debounced search updates the cache key cleanly.
  ///
  /// Copied from [archivedLeads].
  ArchivedLeadsProvider(String query)
    : this._internal(
        (ref) => archivedLeads(ref as ArchivedLeadsRef, query),
        from: archivedLeadsProvider,
        name: r'archivedLeadsProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$archivedLeadsHash,
        dependencies: ArchivedLeadsFamily._dependencies,
        allTransitiveDependencies:
            ArchivedLeadsFamily._allTransitiveDependencies,
        query: query,
      );

  ArchivedLeadsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.query,
  }) : super.internal();

  final String query;

  @override
  Override overrideWith(
    FutureOr<List<LeadListItem>> Function(ArchivedLeadsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ArchivedLeadsProvider._internal(
        (ref) => create(ref as ArchivedLeadsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        query: query,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<LeadListItem>> createElement() {
    return _ArchivedLeadsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ArchivedLeadsProvider && other.query == query;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, query.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ArchivedLeadsRef on AutoDisposeFutureProviderRef<List<LeadListItem>> {
  /// The parameter `query` of this provider.
  String get query;
}

class _ArchivedLeadsProviderElement
    extends AutoDisposeFutureProviderElement<List<LeadListItem>>
    with ArchivedLeadsRef {
  _ArchivedLeadsProviderElement(super.provider);

  @override
  String get query => (origin as ArchivedLeadsProvider).query;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
