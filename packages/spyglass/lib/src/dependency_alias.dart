import 'package:meta/meta.dart';

import 'dependency.dart';
import 'dependency_observer.dart';

/// Registers the exact same instance created by a [TTarget] dependency
/// under an additional key [TAlias] - typically a superclass or an
/// interface [TTarget] implements - so it can also be looked up as
/// [TAlias]: `deps.get<TAlias>()` and `deps.get<TTarget>()` return the
/// identical object.
///
/// Register it alongside the [TTarget] dependency it points at:
///
/// ```dart
/// deps.addAll([
///   Dependency<ServiceImpl>((_, __) => ServiceImpl()),
///   const Alias<ServiceInterface, ServiceImpl>(),
/// ]);
/// ```
///
/// The alias is lazy and stays in sync with [TTarget]: it resolves through
/// `deps.get<TTarget>()`, so it doesn't force early creation, and it
/// automatically follows a later `deps.replace<TTarget>(...)` to the new
/// instance. It never disposes anything itself - [TTarget]'s own
/// [Dependency.dispose] (if any) remains the only thing that tears the
/// shared instance down, when [TTarget] is removed.
///
/// By default `deps.watch<TAlias>()` does NOT react to the shared
/// instance's internal state changes (e.g. a `ChangeNotifier` it happens to
/// be, ticking) - [TAlias] declares nothing about being observable, so
/// nothing is assumed. Pass [createObserver] explicitly if you do want
/// that - e.g. `flutter_spyglass`'s `ListenableDependencyObserver.new`,
/// when [TAlias] itself extends/implements a `Listenable` capability.
///
/// Because this is sugar for a second, independent registration, removing
/// only [TTarget] (e.g. bare `deps.remove<TTarget>()`) leaves the [TAlias]
/// key registered and pointing at what's now a disposed instance -
/// `DependencyUnregistered` doesn't retrigger this alias, by the same rule
/// that governs any other reactive [Dependency.create]. Group them - e.g.
/// in a [Module], or by removing both keys explicitly - so they're always
/// added and removed together.
@immutable
class Alias<TAlias extends Object, TTarget extends TAlias>
    implements Registerable {
  const Alias({this.createObserver, this.tags, this.debugLabel});

  /// See the class-level note on state observability - `null` by default,
  /// meaning `deps.watch<TAlias>()` behaves like `deps.watchInstance<TAlias>()`.
  // ignore: unsafe_variance
  final DependencyObserverFactory<TAlias>? createObserver;

  /// Forwarded to the underlying alias [Dependency] - see [Dependency.tags].
  final List<Object>? tags;

  /// Forwarded to the underlying alias [Dependency] - see
  /// [Dependency.debugLabel]. Defaults to a label naming both types.
  final String? debugLabel;

  @override
  Iterable<Dependency<Object>> get dependencies => [
        Dependency<TAlias>(
          // A tracked read is all that's needed here, for both the initial
          // value and staying in sync afterward - see Dependency.create.
          (deps, _) => deps.watchInstance<TTarget>(),
          createObserver: createObserver,
          tags: tags,
          debugLabel: debugLabel ?? toString(),
        ),
      ];

  @override
  String toString() => 'Alias<$TAlias, $TTarget>';
}
