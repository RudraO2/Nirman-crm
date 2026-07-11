// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'amendments_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$amendmentsForExecutionHash() =>
    r'282fd94481c443db0e504889cb821b38566b1a29';

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

/// Execution-team amendments, optionally filtered to [statusFilter] (db value; ''=all).
///
/// Copied from [amendmentsForExecution].
@ProviderFor(amendmentsForExecution)
const amendmentsForExecutionProvider = AmendmentsForExecutionFamily();

/// Execution-team amendments, optionally filtered to [statusFilter] (db value; ''=all).
///
/// Copied from [amendmentsForExecution].
class AmendmentsForExecutionFamily
    extends Family<AsyncValue<List<ExecutionAmendment>>> {
  /// Execution-team amendments, optionally filtered to [statusFilter] (db value; ''=all).
  ///
  /// Copied from [amendmentsForExecution].
  const AmendmentsForExecutionFamily();

  /// Execution-team amendments, optionally filtered to [statusFilter] (db value; ''=all).
  ///
  /// Copied from [amendmentsForExecution].
  AmendmentsForExecutionProvider call(String statusFilter) {
    return AmendmentsForExecutionProvider(statusFilter);
  }

  @override
  AmendmentsForExecutionProvider getProviderOverride(
    covariant AmendmentsForExecutionProvider provider,
  ) {
    return call(provider.statusFilter);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'amendmentsForExecutionProvider';
}

/// Execution-team amendments, optionally filtered to [statusFilter] (db value; ''=all).
///
/// Copied from [amendmentsForExecution].
class AmendmentsForExecutionProvider
    extends AutoDisposeFutureProvider<List<ExecutionAmendment>> {
  /// Execution-team amendments, optionally filtered to [statusFilter] (db value; ''=all).
  ///
  /// Copied from [amendmentsForExecution].
  AmendmentsForExecutionProvider(String statusFilter)
    : this._internal(
        (ref) => amendmentsForExecution(
          ref as AmendmentsForExecutionRef,
          statusFilter,
        ),
        from: amendmentsForExecutionProvider,
        name: r'amendmentsForExecutionProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$amendmentsForExecutionHash,
        dependencies: AmendmentsForExecutionFamily._dependencies,
        allTransitiveDependencies:
            AmendmentsForExecutionFamily._allTransitiveDependencies,
        statusFilter: statusFilter,
      );

  AmendmentsForExecutionProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.statusFilter,
  }) : super.internal();

  final String statusFilter;

  @override
  Override overrideWith(
    FutureOr<List<ExecutionAmendment>> Function(
      AmendmentsForExecutionRef provider,
    )
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: AmendmentsForExecutionProvider._internal(
        (ref) => create(ref as AmendmentsForExecutionRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        statusFilter: statusFilter,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<ExecutionAmendment>> createElement() {
    return _AmendmentsForExecutionProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is AmendmentsForExecutionProvider &&
        other.statusFilter == statusFilter;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, statusFilter.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin AmendmentsForExecutionRef
    on AutoDisposeFutureProviderRef<List<ExecutionAmendment>> {
  /// The parameter `statusFilter` of this provider.
  String get statusFilter;
}

class _AmendmentsForExecutionProviderElement
    extends AutoDisposeFutureProviderElement<List<ExecutionAmendment>>
    with AmendmentsForExecutionRef {
  _AmendmentsForExecutionProviderElement(super.provider);

  @override
  String get statusFilter =>
      (origin as AmendmentsForExecutionProvider).statusFilter;
}

String _$isExecutionMemberHash() => r'c71120c857d9f6dd7252a0ca8c990c0e81f4d4e9';

/// Whether the caller is on the execution team — drives the You-tab Amendments
/// entry for a non-head member. Fail-soft to false.
///
/// Copied from [isExecutionMember].
@ProviderFor(isExecutionMember)
final isExecutionMemberProvider = AutoDisposeFutureProvider<bool>.internal(
  isExecutionMember,
  name: r'isExecutionMemberProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$isExecutionMemberHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef IsExecutionMemberRef = AutoDisposeFutureProviderRef<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
