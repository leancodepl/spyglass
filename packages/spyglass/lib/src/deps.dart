import 'dart:async' as async;
import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:spyglass/src/event_notifier.dart';

import 'dependency.dart';
import 'deps_events.dart';
import 'deps_exceptions.dart';
import 'managed_dependency.dart';
import 'types.dart';

final _zoneKey = Object();

/// The ambient [Deps] for the current [Zone] - whatever [Deps.runZoned] this
/// code is running under, or [Deps.root] outside of one.
Deps get globalDeps => Zone.current[_zoneKey] as Deps? ?? Deps.root;

/// Alias for [globalDeps].
Deps get deps => globalDeps;

/// Whether this is a debug build - the same computation Flutter's own
/// `kDebugMode` uses, replicated here so it works without a dependency on
/// Flutter (this package doesn't have one, on purpose).
const bool _kIsDebugBuild = !bool.fromEnvironment('dart.vm.product') &&
    !bool.fromEnvironment('dart.vm.profile');

/// Enables tracking of a [Deps] scope's child scopes (created via
/// [Deps.fork]) purely for inspection - see [Deps.debugChildren], and
/// flutter_spyglass's diagnostics extensions for viewing a whole hierarchy.
///
/// This has a real, if small, cost: while enabled, every [Deps] holds a
/// strong reference to each of its live child scopes for as long as they
/// exist, purely so they can be found again for inspection - not something
/// worth paying for by default outside of debugging. It's on by default in
/// debug builds and off in profile/release builds, but it's a compile-time
/// `const`, so:
///  - force it on in profile/release with
///    `--dart-define=spyglass.diagnosticsMode=true`, e.g. to diagnose a
///    scope leak that doesn't reproduce in debug mode;
///  - force it off in debug with
///    `--dart-define=spyglass.diagnosticsMode=false`;
///  - and because it's `const`, whichever branch ends up unreachable is
///    removed entirely by tree shaking - disabled diagnostics tracking
///    costs nothing in the built app.
const bool spyglassDiagnosticsMode = bool.fromEnvironment(
  'spyglass.diagnosticsMode',
  defaultValue: _kIsDebugBuild,
);

/// A box that contains dependencies. Deps can also form a tree-like hierarchy
/// to allow for scoping and overriding dependencies. Reading values from
/// a deps object that it doesn't contain but its ancestors will return
/// the value from the nearest ancestor.
class Deps extends EventNotifier<DepsEvent> {
  /// Returns the current global [Deps] instance. See also [globalDeps].
  factory Deps() => globalDeps;

  /// Input [values] are copied.
  Deps._({
    required this.parent,
    Map<Object, ManagedDependency>? values,
    this.debugLabel,
  }) : _values = {...?values} {
    _setupParentSubscription();
    if (spyglassDiagnosticsMode) {
      parent?._children.add(this);
    }
  }

  /// Creates a completely empty [Deps], detached from the [globalDeps] root
  /// ancestor.
  Deps.detached({String? debugLabel})
      : this._(parent: null, debugLabel: debugLabel);

  /// The root [Deps] instance. This is the ancestor of all other [Deps].
  /// Most likely this is the same as [globalDeps] unless you're using
  /// [Deps.runZoned].
  static final root = Deps.detached();

  /// A label to help identify this scope in logs, error messages, and
  /// diagnostics - e.g. flutter_spyglass's diagnostics extensions, which
  /// prefer it over this scope's identity hash when set. Purely cosmetic;
  /// has no effect on lookup, scoping, or anything else.
  final String? debugLabel;

  void _setupParentSubscription() {
    _parentSubscription =
        parent?.events.where(_isNotShadowedEvent).listen(notify);
  }

  bool _isNotShadowedEvent(DepsEvent e) {
    // Events are shadowed when this scope already has the specified key.
    return switch (e) {
      DependencyRegistered(:final key) => !_isRegisteredHere<Object>(key),
      DependencyUnregistered(:final key) => !_isRegisteredHere<Object>(key),
      DependencyChanged(:final key) => !_isRegisteredHere<Object>(key),
    };
  }

  /// Creates a child scope of this [Deps].
  Deps fork({String? debugLabel}) =>
      Deps._(parent: this, debugLabel: debugLabel);

  /// Run the given [body] in a new [Zone] with this [Deps]
  /// as [globalDeps].
  R runZoned<R>(R Function() body) {
    return async.runZoned(
      body,
      zoneValues: {
        _zoneKey: this,
      },
    );
  }

  /// The scope this one was [fork]ed from, or `null` for [Deps.root] or a
  /// scope created via [Deps.detached].
  final Deps? parent;

  /// Whether this scope has no [parent] - i.e. it's [Deps.root] or was
  /// created via [Deps.detached].
  bool get isRoot => parent == null;
  StreamSubscription<void>? _parentSubscription;
  bool _isDisposed = false;

  @override
  String toString() {
    if (debugLabel case final label?) {
      return "Deps('$label')";
    }
    return isRoot ? 'Deps(root)' : 'Deps(#${identityHashCode(this)})';
  }

  /// Whether [dispose] has already been called on this scope.
  bool get isDisposed => _isDisposed;

  final Map<Object, ManagedDependency> _values;

  /// Live child scopes created via [fork] - only tracked when
  /// [spyglassDiagnosticsMode] is enabled, so this is otherwise always
  /// empty. See [debugChildren].
  final Set<Deps> _children = {};

  /// Snapshot of this scope's direct child scopes created via [fork] that
  /// are still alive - for inspection/diagnostics only, e.g.
  /// flutter_spyglass's diagnostics extensions. Requires
  /// [spyglassDiagnosticsMode] to be enabled; otherwise always empty. See
  /// also [scopeChain] to walk upward (ancestors) instead.
  Iterable<Deps> get debugChildren => List.unmodifiable(_children);

  /// Snapshot of the dependencies registered directly in this scope (not
  /// its ancestors - see [ownEntries]/[getAllEntries]), together with
  /// their current resolution state and whether each was registered
  /// standalone or as part of a group like a [Module] - for
  /// inspection/diagnostics only. Always available regardless of
  /// [spyglassDiagnosticsMode], since it only reflects state this scope
  /// already keeps.
  Iterable<DependencyDiagnostics> get debugOwnDependencies =>
      _values.values.map(
        (managed) => DependencyDiagnostics(
          dependency: managed.dependency,
          value: managed.currentValue,
          origin: managed.origin,
        ),
      );

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw const DepsDisposedException();
    }
  }

  /// Iterate over the scope ancestor chain, starting from this [Deps]
  /// (inclusive) and ending with the root scope.
  Iterable<Deps> get scopeChain sync* {
    Deps? scope = this;
    while (scope != null) {
      yield scope;
      scope = scope.parent;
    }
  }

  /// Gathers all entries accessible from this deps. Potentially expensive,
  /// depending on how deep the tree is and how many entries there are.
  Iterable<Dependency<Object>> getAllEntries() {
    final map = <Type, Dependency<Object>>{};
    for (final scope in scopeChain.toList().reversed) {
      for (final entry in scope.ownEntries) {
        map[entry.key] = entry;
      }
    }
    return map.values;
  }

  /// The [Dependency] descriptors registered directly in this scope - not
  /// its ancestors. See [getAllEntries] to include inherited ones too.
  Iterable<Dependency<Object>> get ownEntries =>
      _values.values.map((e) => e.dependency);

  /// Every entry accessible from this scope (see [getAllEntries]) whose
  /// [Dependency.tags] contains [tag].
  Iterable<Dependency<Object>> getEntriesWithTag(Object tag) =>
      getAllEntries().where((e) => e.tags?.contains(tag) ?? false);

  /// Add or update a dependency.
  ///
  /// If a dependency is already registered under the same [Dependency.key]
  /// with an equal [Dependency.cacheKey] (`null` counts as equal to
  /// `null`), this is a no-op for that entry - the existing value is left
  /// in place rather than disposed and recreated. Use [replace] to force a
  /// replacement unconditionally.
  Unregister add(Registerable registerable) {
    _checkNotDisposed();
    final keys = [
      for (final dependency in registerable.dependencies) dependency.key,
    ];
    for (final dependency in registerable.dependencies) {
      final existing = _values[dependency.key];
      if (existing != null &&
          existing.dependency.cacheKey == dependency.cacheKey) {
        continue;
      }

      final managed = dependency.toManaged(this, registerable);

      remove(managed.key);
      _values[managed.key] = managed;
      notify(DependencyRegistered(key: managed.key));
    }

    return () {
      keys.forEach(remove);
    };
  }

  /// Helper method for adding multiple dependencies at once if you find
  /// calling `deps..add()..add()...` too verbose.
  Unregister addAll(Iterable<Registerable> registerables) {
    final unregisters = <Unregister>[];
    for (final registerable in registerables) {
      final unregister = add(registerable);
      unregisters.add(unregister);
    }

    return () {
      for (final unregister in unregisters) {
        unregister();
      }
    };
  }

  /// Replaces the dependency registered under [Dependency.key], disposing
  /// the previous value and installing [dependency] - unlike [add], this
  /// always replaces, regardless of [Dependency.cacheKey].
  Unregister replace<T extends Object>(Dependency<T> dependency) {
    // Keyed off dependency.key, not the inferred T - when a Dependency<T>
    // flows through an Object-typed reference (e.g. stored in a
    // heterogeneous list), T infers to Object at this call site even though
    // the dependency's own reified type parameter - and thus its key - is
    // still the real one.
    remove<Object>(dependency.key);
    return add(dependency);
  }

  /// Remove the dependency under the specified key - or, for a
  /// [Registerable] (a [Module] or a [Dependency]), every dependency it
  /// describes, as a single unit.
  ///
  /// [keyOrRegisterable] can be:
  ///  - omitted, to remove the dependency registered under [T];
  ///  - a [Type], to remove the dependency registered under that type
  ///    without needing the generic parameter - e.g. `deps.remove(Foo)`;
  ///  - a [Registerable], to remove every dependency it groups - e.g.
  ///    `deps.remove(myModule)` removes every dependency that module lists.
  ///    This doesn't require holding onto the [Unregister] callback
  ///    returned by [add]/[addAll]: any [Registerable] describing the same
  ///    dependency types removes the same keys, since dependencies are
  ///    looked up by type, not by the identity of the [Registerable] that
  ///    originally registered them.
  ///
  /// A no-op once this [Deps] has been disposed - same as removing a key
  /// that was never registered - rather than throwing, since callers doing
  /// their own cleanup (e.g. a widget's unmount effect calling an
  /// [Unregister] callback) shouldn't have to carefully order that against
  /// [dispose] to avoid a crash.
  void remove<T extends Object>([Object? keyOrRegisterable]) {
    if (_isDisposed) {
      return;
    }
    if (keyOrRegisterable is Registerable) {
      for (final dependency in keyOrRegisterable.dependencies) {
        remove<Object>(dependency.key);
      }
      return;
    }
    if (keyOrRegisterable != null && keyOrRegisterable is! Type) {
      throw ArgumentError.value(
        keyOrRegisterable,
        'keyOrRegisterable',
        'must be a Type, a Registerable (e.g. a Module or Dependency), or '
            'omitted',
      );
    }
    final effectiveKey = (keyOrRegisterable as Type?) ?? T;
    final value = _values.remove(effectiveKey);
    unawaited(Future.sync(() => value?.dispose()));
    if (value != null) {
      notify(DependencyUnregistered(key: effectiveKey));
    }
  }

  /// Checks whether a dependency with the given key is registered in this
  /// [Deps] or any of its ancestors.
  bool isRegistered<T>([Type? key]) {
    final effectiveKey = key ?? T;

    return scopeChain.any((scope) => scope._values.containsKey(effectiveKey));
  }

  /// Unlike [isRegistered] this method only checks if the dependency is
  /// registered in this [Deps] instance, not its ancestors.
  bool _isRegisteredHere<T>([DependencyKey? key]) {
    final effectiveKey = key ?? T;

    return _values.containsKey(effectiveKey);
  }

  /// Helper method for obtaining a [ManagedDependency] instance backing
  /// the dependency of the specified type.
  ManagedDependency<T>? _tryGetDependency<T extends Object>([
    DependencyKey? key,
  ]) {
    final effectiveKey = key ?? T;
    for (final scope in scopeChain) {
      final value = scope._values[effectiveKey];
      if (value != null) {
        return value as ManagedDependency<T>;
      }
    }
    return null;
  }

  /// {@template spyglass_deps_get}
  /// Returns the resolved value of the specified dependency. If the dependency
  /// is not yet initialized, i.e. its [Dependency.create] method has not
  /// resolved yet, this method will throw a [DependencyNotResolvedException].
  ///
  /// If the dependency is not registered, this method will throw
  /// a [DependencyNotRegisteredException]. To see if a dependency is
  /// registered, use [isRegistered].
  /// {@endtemplate}
  T get<T extends Object>([DependencyKey? key]) {
    final effectiveKey = key ?? T;
    final dependency = _tryGetDependency<T>(key);
    if (dependency == null) {
      throw DependencyNotRegisteredException(effectiveKey);
    }
    final value = dependency.tryResolve();
    if (value == null) {
      throw DependencyNotResolvedException(effectiveKey);
    }
    return value;
  }

  /// Returns the resolved value of the specified dependency, or `null` if
  /// it isn't registered - unlike [get], which throws
  /// [DependencyNotRegisteredException] in that case. Like [get], this
  /// triggers creation of the dependency if it hasn't been created yet.
  ///
  /// To read a value without triggering creation as a side effect, use
  /// [peek] instead.
  T? tryGet<T extends Object>([DependencyKey? key]) {
    final dependency = _tryGetDependency<T>(key);
    return dependency?.tryResolve();
  }

  /// Returns the current value of the specified dependency if it's already
  /// been created, or `null` otherwise - whether because it isn't
  /// registered or because it's registered but hasn't been resolved yet.
  /// Unlike [get] and [tryGet], this never triggers creation.
  T? peek<T extends Object>([DependencyKey? key]) =>
      _tryGetDependency<T>(key)?.currentValue;

  T? _tryResolveValue<T extends Object>([DependencyKey? key]) {
    final dependency = _tryGetDependency<T>(key);
    return dependency?.tryResolve();
  }

  /// Emits (with no payload) whenever the [ManagedDependency] backing
  /// [effectiveKey] might have appeared, been replaced, or moved - i.e.
  /// registration events, not internal state changes. These are rare
  /// compared to state changes, so it's fine for every subscriber of
  /// [watch]/[watchInstance] to filter this shared stream individually.
  Stream<void> _registrations(DependencyKey effectiveKey) async* {
    yield null;
    await for (final event in events) {
      final matches = switch (event) {
        DependencyChanged(:final key) => key == effectiveKey,
        DependencyRegistered(:final key) => key == effectiveKey,
        DependencyUnregistered() => false,
      };
      if (matches) {
        yield null;
      }
    }
  }

  /// Watch a dependency's registration only - for watching multiple
  /// dependencies at once see extensions [watch2], [watch3] etc. Emits
  /// whenever the dependency itself is (re-)registered, i.e. when
  /// [Deps.add] or [Deps.replace] installs a new value under this key - but
  /// NOT when a value that happens to be a `ChangeNotifier`/`Listenable`
  /// fires its own internal notifications. See [watch] for that.
  ///
  /// Cheaper than [watch] when you only care which instance is currently
  /// registered, not what it's internally doing - e.g. watching which auth
  /// service is active without rebuilding on its every internal tick.
  Stream<T> watchInstance<T extends Object>({DependencyKey? key}) {
    final effectiveKey = key ?? T;
    return _detach(_registrations(effectiveKey).expand((_) sync* {
      final value = _tryResolveValue<T>(key);
      if (value != null) {
        yield value;
      }
    }));
  }

  /// Watch a dependency fully. Emits both when the dependency is
  /// (re-)registered (see [watchInstance]) AND whenever the resolved
  /// value's `DependencyObserver` (see [Dependency.createObserver]) reports
  /// an internal state change - e.g. a wrapped `ChangeNotifier`/`Listenable`
  /// firing its own notifications. Internal state changes are delivered by
  /// subscribing directly to the backing [ManagedDependency]'s own stream
  /// (shared by every subscriber of this key), not by broadcasting through
  /// every dependency's shared event stream - so watching this key doesn't
  /// cost anything when an unrelated dependency's state changes.
  Stream<T> watch<T extends Object>({DependencyKey? key}) {
    final effectiveKey = key ?? T;
    return _switchToLatest(_registrations(effectiveKey), () {
      final managed = _tryGetDependency<T>(key);
      return (managed, managed?.watch());
    });
  }

  /// Rewraps [source] behind a fresh [StreamController] so cancelling the
  /// result doesn't wait on cancelling [source] itself.
  ///
  /// [source] is built out of `async*`/`await for` over [events] (a
  /// broadcast controller). Cancelling a subscription to such a stream can
  /// hang indefinitely under some zones (observed under `package:test`,
  /// independent of anything specific to this package - a minimal
  /// `async*`-over-broadcast-stream repro reproduces it too), because
  /// finishing the cancellation depends on the generator's `await for` loop
  /// actually resuming to notice it's been cancelled, which apparently
  /// doesn't happen in every zone. Detaching cancellation like this - fire
  /// it and don't wait - avoids depending on that ever resolving.
  static Stream<T> _detach<T extends Object>(Stream<T> source) {
    late final StreamController<T> controller;
    StreamSubscription<T>? sourceSub;

    controller = StreamController<T>.broadcast(
      onListen: () => sourceSub =
          source.listen(controller.add, onError: controller.addError),
      onCancel: () {
        unawaited(sourceSub?.cancel());
        unawaited(controller.close());
      },
    );

    return controller.stream;
  }

  /// Equivalent to `triggers.switchMap((_) => resolve().$2 ?? Stream.empty())`,
  /// hand-rolled to avoid rxdart's switchMap overhead - re-registration
  /// (what [triggers] fires on) is rare, so a plain callback-based resubscribe
  /// is cheaper than a full operator per subscriber.
  ///
  /// [resolve] returns an identity token alongside the stream - NOT the
  /// stream itself, since e.g. a `BehaviorSubject.stream` getter returns a
  /// fresh wrapper object on every access, so comparing streams for
  /// `identical` would never dedupe anything.
  static Stream<T> _switchToLatest<T extends Object>(
    Stream<void> triggers,
    (Object?, Stream<T>?) Function() resolve,
  ) {
    late final StreamController<T> controller;
    StreamSubscription<void>? triggerSub;
    StreamSubscription<T>? innerSub;
    Object? lastId;

    void resubscribe() {
      final (id, stream) = resolve();
      if (identical(id, lastId)) {
        // [triggers] can fire more than once for what's really the same
        // underlying value becoming available - e.g. a lazily-created
        // dependency's first resolution fires both DependencyRegistered and
        // DependencyChanged. Resolving to the same identity twice means
        // nothing actually changed, so skip re-subscribing - a `watch()`
        // BehaviorSubject replays its current value to every fresh
        // subscriber, so a redundant resubscribe here would double-deliver.
        return;
      }
      lastId = id;
      unawaited(innerSub?.cancel());
      innerSub = stream?.listen(controller.add, onError: controller.addError);
    }

    controller = StreamController<T>.broadcast(
      onListen: () => triggerSub = triggers.listen((_) => resubscribe()),
      onCancel: () {
        unawaited(triggerSub?.cancel());
        unawaited(innerSub?.cancel());
        unawaited(controller.close());
      },
    );

    return controller.stream;
  }

  /// Returns a future that resolves when all the specified dependencies are
  /// initialized and can be retrieved using synchronous [get]. Note that
  /// this triggers the resolution of lazily initialized dependencies.
  ///
  /// This method is useful e.g. when you want to ensure certain services
  /// are initialized before the application starts.
  ///
  ///
  /// ```dart
  /// Future<void> main() async {
  ///   // register deps here
  ///   deps.add(/* ... */);
  ///   // ...
  ///
  ///   await deps.ensureResolved([ServiceA, ServiceB]);
  ///
  ///   runApp(MyApp());
  /// }
  /// ```
  void ensureResolved(Iterable<DependencyKey> keys) {
    keys.forEach(get);
  }

  /// Dispose of the [Deps] instance and all dependencies it contains.
  @override
  Future<void> dispose() {
    _isDisposed = true;
    _parentSubscription?.cancel();
    if (spyglassDiagnosticsMode) {
      parent?._children.remove(this);
    }
    for (final value in _values.values) {
      unawaited(value.dispose());
    }
    return super.dispose();
  }
}

/// [Deps.watchInstance]-based helpers for watching several dependencies at
/// once - [watch2] through [watch5] cover the common fixed-arity cases;
/// [watchMany] is the general, dynamic-arity version they're built on.
extension DepsWatchMany on Deps {
  /// Combines the latest [watchInstance] value of each of [types]. Uses
  /// [watchInstance], not [watch] - each type's own internal state
  /// changes are ignored, only registration-level changes are combined.
  /// This is also what powers [Dependency.create] recomputing for computed
  /// dependencies (via `DepsReader.watchInstance`, internally): a computed
  /// value recomputes when an upstream dependency is replaced, not on
  /// every tick of an upstream `ChangeNotifier`.
  Stream<List<Object>> watchMany(List<Type> types) => Rx.combineLatest(
        types.map((type) => watchInstance(key: type)),
        (values) => values,
      );

  /// Combines the latest [watchInstance] value of [A] and [B] - see
  /// [watchMany].
  Stream<(A, B)> watch2<A, B>() =>
      watchMany([A, B]).map((list) => (list[0] as A, list[1] as B));

  /// Combines the latest [watchInstance] value of [A], [B] and [C] - see
  /// [watchMany].
  Stream<(A, B, C)> watch3<A, B, C>() => watchMany([A, B, C])
      .map((list) => (list[0] as A, list[1] as B, list[2] as C));

  /// Combines the latest [watchInstance] value of [A] through [D] - see
  /// [watchMany].
  Stream<(A, B, C, D)> watch4<A, B, C, D>() => watchMany([A, B, C, D])
      .map((list) => (list[0] as A, list[1] as B, list[2] as C, list[3] as D));

  /// Combines the latest [watchInstance] value of [A] through [E] - see
  /// [watchMany].
  Stream<(A, B, C, D, E)> watch5<A, B, C, D, E>() =>
      watchMany([A, B, C, D, E]).map(
        (list) => (
          list[0] as A,
          list[1] as B,
          list[2] as C,
          list[3] as D,
          list[4] as E
        ),
      );
}
