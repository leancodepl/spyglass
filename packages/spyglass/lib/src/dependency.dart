import 'dart:async';

import 'package:meta/meta.dart';

import 'dependency_observer.dart';
import 'deps.dart';
import 'managed_dependency.dart';
import 'types.dart';

/// An immutable object describing a dependency. It can be registered in [Deps]
/// by using [Deps.add].
@immutable
class Dependency<T extends Object> implements Registerable {
  /// An immutable object describing a dependency. It can be registered in [Deps]
  /// by using [Deps.add].
  const Dependency(
    this.create, {
    this.observe,
    this.update,
    this.dispose,
    this.tags,
    this.debugLabel,
    this.cacheKey,
    DependencyObserverFactory<T>? createObserver,
  })  : createObserverFn = createObserver,
        assert(
          observe != null || update == null,
          'when must be provided if update is provided',
        );

  /// An immutable object describing a dependency. It can be registered in [Deps]
  /// by using [Deps.add].
  ///
  /// This is a shorthand for creating a dependency that doesn't change
  /// over time and does not need to be lazily created.
  Dependency.value(
    T value, {
    this.tags,
    this.dispose,
    this.debugLabel,
    this.cacheKey,
    DependencyObserverFactory<T>? createObserver,
  })  : create = ((_) => value),
        observe = null,
        update = null,
        createObserverFn = createObserver;

  /// The key or type of the dependency. It is a unique identifier for the
  /// dependency in its [Deps].
  DependencyKey get key => T;

  /// An additional piece of identity, compared via `==`, that [Deps.add]
  /// uses (alongside [key]) to decide whether a new [Dependency] registered
  /// under the same key represents a genuine change or should be left
  /// alone - analogous to Flutter's `Widget.key`. Defaults to `null`, which
  /// is only ever considered equal to another `null` cacheKey - so by
  /// default, calling [Deps.add] again under the same key with no cacheKey
  /// specified is treated as "unchanged," and the existing value is left in
  /// place rather than disposed and recreated. Use [Deps.replace] to force
  /// a replacement regardless of cacheKey.
  final Object? cacheKey;

  /// Tags can be used to categorize dependencies and perform operations on them.
  /// For example, you can use a 'startup' tag to mark dependencies that need to be
  /// initialized before the application starts. Then, use [Deps.ensureResolved] to
  /// wait for them to be resolved before proceeding.
  final List<Object>? tags;

  /// Creates a new instance of [T]. You can use provided [Deps] to obtain
  /// required dependencies. This callback can be asynchronous to perform
  /// long running initialization or await another dependency.
  final T Function(Deps deps) create;

  /// Updates or creates a new instance of the dependency in reaction to
  /// changes in other dependencies specified by [observe].
  // ignore: unsafe_variance
  final T Function(Deps deps, T oldValue)? update;

  /// Use one of [Deps.watchInstance], [DepsWatchMany.watch2] etc. to
  /// specify which changes you want to observe.
  final List<DependencyKey>? observe;

  /// Perform actions to clean up after the object is no longer needed.
  // ignore: unsafe_variance, avoid_futureor_void
  final FutureOr<void> Function(T value)? dispose;

  /// A debug label to help identify the dependency in logs.
  final String? debugLabel;

  // reason: no other way
  // ignore: unsafe_variance
  final DependencyObserverFactory<T>? createObserverFn;

  /// NOTE
  /// This method is required to retain generic type information when creating
  /// a [ManagedDependency] instance in e.g. [Deps.addAll]
  // ignore: comment_references
  /// and [DepsProvider.register] from flutter_spyglass.
  ///
  /// [origin] is the [Registerable] that was actually passed to
  /// [Deps.add]/[Deps.addAll] - either this same [Dependency] (when it was
  /// registered standalone) or e.g. a [Module] (when it was registered as
  /// part of a group) - see [DependencyDiagnostics.isStandalone].
  ///
  /// Package-internal - not `_`-private only because [Deps.add] (a
  /// different library, now that spyglass's source is split across files)
  /// needs to call it too.
  @internal
  ManagedDependency<T> toManaged(Deps deps, Registerable origin) =>
      ManagedDependency(this, deps, origin);

  /// Returns `null` if this dependency has no [createObserverFn], i.e. it
  /// never reports internal state changes - see [DependencyObserver].
  DependencyObserver<T>? createObserver(T value) =>
      createObserverFn?.call(value);

  @override
  String toString() {
    return "Dependency<$T>('$debugLabel')";
  }

  @override
  Iterable<Dependency<Object>> get dependencies => [this];
}

/// A snapshot of a single registered dependency's descriptor and current
/// resolution state, for inspection/diagnostics only - see
/// [Deps.debugOwnDependencies], which is what flutter_spyglass's
/// diagnostics extensions build on to show a [Deps] hierarchy.
@immutable
class DependencyDiagnostics {
  const DependencyDiagnostics({
    required this.dependency,
    required this.value,
    required this.origin,
  });

  /// The registered dependency's immutable descriptor.
  final Dependency<Object> dependency;

  DependencyKey get key => dependency.key;

  /// The dependency's current resolved value - same as `Deps.peek` would
  /// return for [key] - or `null` if it's registered but hasn't been
  /// created yet.
  final Object? value;

  bool get isResolved => value != null;

  /// The [Registerable] this dependency was actually passed to
  /// [Deps.add]/[Deps.addAll] as part of - [dependency] itself when it was
  /// registered on its own, or e.g. a [Module] when it was registered as
  /// part of a group. See [isStandalone] and [module].
  final Registerable origin;

  /// Whether this dependency was registered on its own - i.e. passed
  /// directly to [Deps.add]/[Deps.addAll] - rather than grouped inside
  /// another [Registerable] like a [Module].
  bool get isStandalone => identical(origin, dependency);

  /// The [Module] this dependency was registered as part of, or `null` if
  /// it was registered standalone (see [isStandalone]) or grouped by some
  /// other, non-[Module] [Registerable].
  Module? get module => origin is Module ? origin as Module : null;

  @override
  String toString() {
    final resolution = isResolved ? 'resolved: $value' : 'not yet resolved';
    final grouping = isStandalone ? 'standalone' : 'part of $origin';
    return 'DependencyDiagnostics($dependency, $resolution, $grouping)';
  }
}

/// Groups several [Dependency] descriptors so they can be registered and
/// removed together as one unit - see [Deps.add]/[Deps.addAll] and
/// [Deps.remove], which also accepts a [Module] to remove every dependency
/// it lists. [DependencyDiagnostics.module] reports which [Module] (if any)
/// a given registered dependency came from.
class Module implements Registerable {
  Module(
    this.dependencies, {
    this.debugLabel,
  });

  @override
  final List<Dependency<Object>> dependencies;

  final String? debugLabel;

  @override
  String toString() => "Module('$debugLabel')";
}

/// Something that can be passed to [Deps.add]/[Deps.addAll] (and removed via
/// [Deps.remove]) - implemented by [Dependency] and [Module].
///
/// To create one, use [Dependency.new], [Dependency.value], or
/// [Module.new].
abstract class Registerable {
  Iterable<Dependency<Object>> get dependencies;
}
