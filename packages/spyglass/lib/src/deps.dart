import 'dart:async' as async;
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';
import 'package:spyglass/src/event_notifier.dart';

final _zoneKey = Object();
Deps get globalDeps => Zone.current[_zoneKey] as Deps? ?? Deps.root;

/// Alias for [globalDeps].
Deps get deps => globalDeps;

typedef DependencyKey = Type;

/// Callback to unregister a dependency. It will be disposed of automatically.
typedef Unregister = void Function();

/// A factory function to create a [DependencyObserver] for a dependency.
typedef DependencyObserverFactory<T extends Object> = DependencyObserver<T>?
    Function(T value);

/// Event emitted by [Deps] when a dependency is registered, unregistered,
/// or changed.
sealed class DepsEvent {}

/// Event emitted by [Deps] when a dependency is registered. It does not mean
/// its value can be read by [Deps.get] if the dependency is asynchronous.
/// When an async dependency is resolved it will be followed by
/// a [DependencyChanged] event.
final class DependencyRegistered extends Equatable implements DepsEvent {
  const DependencyRegistered({
    required this.key,
  });

  /// The key of the dependency that was registered.
  final DependencyKey key;

  @override
  List<Object?> get props => [key];
}

/// Event emitted by [Deps] when a dependency is unregistered.
final class DependencyUnregistered extends Equatable implements DepsEvent {
  const DependencyUnregistered({
    required this.key,
  });

  /// The key of the dependency that was unregistered.
  final DependencyKey key;

  @override
  List<Object?> get props => [key];
}

/// Event emitted by [Deps] when a dependency value is changed, i.e.
/// as a result of the [Dependency.create] or [Dependency.update] callback.
final class DependencyChanged extends Equatable implements DepsEvent {
  const DependencyChanged({
    required this.key,
  });

  final DependencyKey key;

  @override
  List<Object?> get props => [key];
}

/// Thrown by [Deps.get] and [Deps.tryGet] when no dependency is registered
/// under [key] in this [Deps] scope or any of its ancestors.
class DependencyNotRegisteredException implements Exception {
  const DependencyNotRegisteredException(this.key);

  /// The key that was looked up.
  final DependencyKey key;

  @override
  String toString() =>
      'DependencyNotRegisteredException: No dependency is registered for '
      '$key in this Deps scope or any of its ancestors.\n'
      'Check that it was added via Deps.add/Deps.replace, or listed in the '
      'register: of a DepsProvider above this point in the widget tree - '
      'and that the type matches exactly, since Deps looks up by exact '
      'runtime Type.';
}

/// Thrown by [Deps.get] when [key] is registered but its value hasn't
/// finished resolving yet - e.g. [Dependency.create] is asynchronous and
/// still running.
class DependencyNotResolvedException implements Exception {
  const DependencyNotResolvedException(this.key);

  /// The key that was looked up.
  final DependencyKey key;

  @override
  String toString() =>
      'DependencyNotResolvedException: $key is registered, but its value '
      "hasn't resolved yet - Dependency.create is still running (likely "
      'asynchronous).\n'
      'Use Deps.tryGet for a nullable result instead of throwing, or await '
      'Deps.ensureResolved([$key]) before calling Deps.get.';
}

/// Thrown when an operation needs this [Deps] scope to still be alive, but
/// [Deps.dispose] has already been called on it - by [Deps.add] (adding to a
/// disposed scope makes no sense) and by [Deps.get]/[Deps.tryGet] (resolving
/// a value from a scope whose dependencies have all been torn down doesn't
/// either).
class DepsDisposedException implements Exception {
  const DepsDisposedException({this.key});

  /// The dependency key involved, if the failing operation was about a
  /// specific key (e.g. [Deps.get]) rather than the scope as a whole (e.g.
  /// [Deps.add]).
  final DependencyKey? key;

  @override
  String toString() {
    final about = key == null ? '' : ' (while resolving $key)';
    return 'DepsDisposedException: This Deps scope has already been '
        'disposed$about and can no longer register or resolve '
        'dependencies.\n'
        "If this came from a widget, you're likely holding onto a Deps "
        'reference that outlived its DepsProvider - e.g. a callback that '
        'captured a Deps and ran after the provider that owned it unmounted.';
  }
}

/// Thrown when resolving [key] re-enters its own [Dependency.create] before
/// the first call has finished - i.e. a dependency, directly or indirectly,
/// depends on itself.
class DependencyCycleException implements Exception {
  const DependencyCycleException(this.key);

  /// The key whose creation cycled back on itself.
  final DependencyKey key;

  @override
  String toString() =>
      'DependencyCycleException: Creating $key triggered another attempt to '
      'resolve $key before the first one finished.\n'
      'This usually means Dependency.create for $key - directly, or '
      'indirectly via Deps.get inside it - depends on itself.';
}

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

  /// Use one of [Deps.trackInstance], [DepsTrackMany.track2] etc. to
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
  ManagedDependency<T> _toManaged(Deps deps) => ManagedDependency(this, deps);

  /// Returns `null` if this dependency has no [createObserverFn], i.e. it
  /// never reports internal state changes - see [DependencyObserver].
  DependencyObserver<T>? createObserver(T value) => createObserverFn?.call(value);

  @override
  String toString() {
    return "Dependency<$T>('$debugLabel')";
  }

  @override
  Iterable<Dependency<Object>> get dependencies sync* {
    yield this;
  }
}

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
  }) : _values = {...?values} {
    _setupParentSubscription();
  }

  /// Creates a completely empty [Deps], detached from the [globalDeps] root
  /// ancestor.
  Deps.detached() : this._(parent: null);

  /// The root [Deps] instance. This is the ancestor of all other [Deps].
  /// Most likely this is the same as [globalDeps] unless you're using
  /// [Deps.runZoned].
  static final root = Deps.detached();

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
  Deps fork() => Deps._(parent: this);

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

  final Deps? parent;
  bool get isRoot => parent == null;
  StreamSubscription<void>? _parentSubscription;
  bool _isDisposed = false;

  final Map<Object, ManagedDependency> _values;

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

  Iterable<Dependency<Object>> get ownEntries =>
      _values.values.map((e) => e.dependency);

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
      if (existing != null && existing.dependency.cacheKey == dependency.cacheKey) {
        continue;
      }

      final managed = dependency._toManaged(this);

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

  /// Remove the dependency under the specified key.
  ///
  /// Note: This method might not always be invoked with the generic parameter,
  /// so the type/key can also be specified as a parameter.
  ///
  /// A no-op once this [Deps] has been disposed - same as removing a key
  /// that was never registered - rather than throwing, since callers doing
  /// their own cleanup (e.g. a widget's unmount effect calling an
  /// [Unregister] callback) shouldn't have to carefully order that against
  /// [dispose] to avoid a crash.
  void remove<T extends Object>([Type? key]) {
    if (_isDisposed) {
      return;
    }
    final effectiveKey = key ?? T;
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

  /// {@macro spyglass_deps_get}
  ///
  /// Alias for [get].
  T call<T extends Object>() => get<T>();

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
      _tryGetDependency<T>(key)?._currentValue;

  T? _tryResolveValue<T extends Object>([DependencyKey? key]) {
    final dependency = _tryGetDependency<T>(key);
    return dependency?.tryResolve();
  }

  /// Emits (with no payload) whenever the [ManagedDependency] backing
  /// [effectiveKey] might have appeared, been replaced, or moved - i.e.
  /// registration events, not internal state changes. These are rare
  /// compared to state changes, so it's fine for every subscriber of
  /// [track]/[trackInstance] to filter this shared stream individually.
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

  /// Track a dependency's registration only - for watching multiple
  /// dependencies at once see extensions [track2], [track3] etc. Emits
  /// whenever the dependency itself is (re-)registered, i.e. when
  /// [Deps.add] or [Deps.replace] installs a new value under this key - but
  /// NOT when a value that happens to be a `ChangeNotifier`/`Listenable`
  /// fires its own internal notifications. See [track] for that.
  ///
  /// Cheaper than [track] when you only care which instance is currently
  /// registered, not what it's internally doing - e.g. watching which auth
  /// service is active without rebuilding on its every internal tick.
  Stream<T> trackInstance<T extends Object>({DependencyKey? key}) {
    final effectiveKey = key ?? T;
    return _detach(_registrations(effectiveKey).expand((_) sync* {
      final value = _tryResolveValue<T>(key);
      if (value != null) {
        yield value;
      }
    }));
  }

  /// Track a dependency fully. Emits both when the dependency is
  /// (re-)registered (see [trackInstance]) AND whenever the resolved
  /// value's [DependencyObserver] (see [Dependency.createObserver]) reports
  /// an internal state change - e.g. a wrapped `ChangeNotifier`/`Listenable`
  /// firing its own notifications. Internal state changes are delivered by
  /// subscribing directly to the backing [ManagedDependency]'s own stream
  /// (shared by every subscriber of this key), not by broadcasting through
  /// every dependency's shared event stream - so watching this key doesn't
  /// cost anything when an unrelated dependency's state changes.
  Stream<T> track<T extends Object>({DependencyKey? key}) {
    final effectiveKey = key ?? T;
    return _switchToLatest(_registrations(effectiveKey), () {
      final managed = _tryGetDependency<T>(key);
      return (managed, managed?.track());
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
      onListen: () =>
          sourceSub = source.listen(controller.add, onError: controller.addError),
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
        // nothing actually changed, so skip re-subscribing - a `track()`
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
    for (final value in _values.values) {
      unawaited(value.dispose());
    }
    return super.dispose();
  }
}

extension DepsTrackMany on Deps {
  /// Combines the latest [trackInstance] value of each of [types]. Uses
  /// [trackInstance], not [track] - each type's own internal state
  /// changes are ignored, only registration-level changes are combined.
  /// This is what powers [Dependency.observe]/[Dependency.update] for
  /// computed dependencies: a computed value recomputes when an upstream
  /// dependency is replaced, not on every tick of an upstream
  /// `ChangeNotifier`.
  Stream<List<Object>> trackMany(List<Type> types) => Rx.combineLatest(
        types.map((type) => trackInstance(key: type)),
        (values) => values,
      );

  Stream<(A, B)> track2<A, B>() =>
      trackMany([A, B]).map((list) => (list[0] as A, list[1] as B));

  Stream<(A, B, C)> track3<A, B, C>() => trackMany([A, B, C])
      .map((list) => (list[0] as A, list[1] as B, list[2] as C));

  Stream<(A, B, C, D)> track4<A, B, C, D>() => trackMany([A, B, C, D])
      .map((list) => (list[0] as A, list[1] as B, list[2] as C, list[3] as D));

  Stream<(A, B, C, D, E)> track5<A, B, C, D, E>() =>
      trackMany([A, B, C, D, E]).map(
        (list) => (
          list[0] as A,
          list[1] as B,
          list[2] as C,
          list[3] as D,
          list[4] as E
        ),
      );
}

/// This class helps manage lifecycle of a single dependency. It is tightly
/// coupled with [Deps]. It's an internal structure and it should never be
/// exposed as part of the public API.
@internal
class ManagedDependency<T extends Object> {
  ManagedDependency(this.dependency, this.deps);

  final Dependency<T> dependency;
  final Deps deps;

  DependencyKey get key => dependency.key;

  /// This dependency's own value stream, shared by every subscriber that
  /// tracks this key with [Deps.track] - see also [track] below. Created
  /// lazily, on the first call to [track], so a dependency that's only ever
  /// plain-read via [Deps.get] - the common "just a service locator" case -
  /// never pays for a [DependencyObserver] or a [BehaviorSubject] it doesn't
  /// need.
  BehaviorSubject<T>? _controller;
  StreamSubscription<void>? _observeSubscription;
  T? _currentValue;

  /// One observer for the current [_currentValue], not one per subscriber -
  /// see [DependencyObserver]. Only created once [track] has been called at
  /// least once (see [_controller]); recreated whenever [_currentValue]
  /// itself is replaced (either by re-registration or by the
  /// [Dependency.update] chain below).
  DependencyObserver<T>? _stateObserver;
  bool _debugCreateCalled = false;
  bool _isDisposed = false;

  /// No-op unless [track] has already been called at least once for this
  /// dependency - see [_controller].
  void _attachStateObserverIfTracked(T value) {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    _stateObserver = dependency.createObserver(value)
      ?..attach(() => controller.add(value));
  }

  void _ensureInitialized() {
    if (_isDisposed) {
      throw DepsDisposedException(key: key);
    }
    if (_currentValue != null) {
      return;
    }
    if (_debugCreateCalled) {
      throw DependencyCycleException(key);
    }
    _debugCreateCalled = true;
    _currentValue = dependency.create(deps);
    // reason: ManagedDependency and Deps work in tandem
    // ignore: invalid_use_of_protected_member
    deps.notify(DependencyChanged(key: key));

    if ((dependency.observe, dependency.update)
        case (final observe?, final update?)) {
      unawaited(_observeSubscription?.cancel());
      _observeSubscription = deps
          .trackMany(observe)
          .map((_) => update(deps, _currentValue!))
          .listen((newValue) {
        if (_isDisposed) {
          return;
        }
        if (newValue != _currentValue) {
          final oldObserver = _stateObserver;
          _currentValue = newValue;
          _stateObserver = null;
          unawaited(oldObserver?.dispose());
          _attachStateObserverIfTracked(newValue);
          _controller?.add(newValue);
          // reason: ManagedDependency and Deps work in tandem
          // ignore: invalid_use_of_protected_member
          deps.notify(DependencyChanged(key: key));
        }
      });
    }
  }

  T resolve() {
    _ensureInitialized();
    return switch (_currentValue) {
      final T value => value,
      null => throw StateError('Initialization error. This is a bug.'),
    };
  }

  T? tryResolve() {
    _ensureInitialized();
    return _currentValue;
  }

  Stream<T> track() {
    _ensureInitialized();
    var controller = _controller;
    if (controller == null) {
      controller = _controller = BehaviorSubject<T>();
      _attachStateObserverIfTracked(_currentValue!);
      controller.add(_currentValue!);
    }
    return controller.stream;
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _observeSubscription?.cancel();
    await _controller?.close();
    await _stateObserver?.dispose();
    if ((dependency.dispose, _currentValue)
        case (final dispose?, final value?)) {
      final resolvedValue = value;
      await dispose(resolvedValue);
    }
  }
}

/// Observes internal state changes of an already-resolved dependency value -
/// e.g. a wrapped `ChangeNotifier`/`Listenable` firing its own notifications
/// - as opposed to the value itself being replaced. See
/// [Dependency.createObserver].
///
/// The framework creates and disposes exactly one observer per resolved
/// value, not one per subscriber to [Deps.track]; call [notifyStateChanged]
/// whenever the observed value's state changes and every current
/// [Deps.track] subscriber for this key is notified.
abstract class DependencyObserver<T extends Object> {
  void Function()? _onChanged;

  /// Wires this observer up to its owning [ManagedDependency]. Called by the
  /// framework right after construction - implementers should not call this.
  @internal
  void attach(void Function() onChanged) {
    _onChanged = onChanged;
  }

  /// Call this whenever the observed value's internal state changes, to
  /// notify anyone tracking this dependency via [Deps.track] - without
  /// needing to know about [Deps] or [ManagedDependency] directly.
  @protected
  void notifyStateChanged() {
    _onChanged?.call();
  }

  Future<void> dispose();
}

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

abstract class Registerable {
  Iterable<Dependency<Object>> get dependencies;
}
