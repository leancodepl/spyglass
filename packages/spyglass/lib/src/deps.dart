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
    DependencyObserverFactory<T>? createObserver,
  })  : create = ((_) => value),
        observe = null,
        update = null,
        createObserverFn = createObserver;

  /// The key or type of the dependency. It is a unique identifier for the
  /// dependency in its [Deps].
  DependencyKey get key => T;

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

  /// Use one of [Deps.observe], [DepsObserveMany.observe2] etc. to specify which
  /// changes you want to observe.
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
  /// a [ManagedDependency] instance in e.g. [Deps.addMany]
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

  final Map<Object, ManagedDependency> _values;

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

  /// Peek at the value of a dependency without resolving it.
  T? peek<T extends Object>([DependencyKey? key]) =>
      _tryGetDependency<T>(key)?._currentValue;

  /// Add or update a dependency.
  Unregister add(Registerable registerable) {
    final keys = [
      for (final dependency in registerable.dependencies) dependency.key,
    ];
    for (final dependency in registerable.dependencies) {
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
  Unregister addMany(Iterable<Registerable> registerables) {
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

  /// Alias for [add]. Use it to add more semantic meaning to an update.
  Unregister replace<T extends Object>(Dependency<T> dependency) =>
      add(dependency);

  /// Remove the dependency under the specified key.
  ///
  /// Note: This method might not always be invoked with the generic parameter,
  /// so the type/key can also be specified as a parameter.
  void remove<T extends Object>([Type? key]) {
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
  /// resolved yet, this method will throw a [StateError].
  ///
  /// If the dependency is not registered, this method will throw
  /// an [ArgumentError]. To see if a dependency is registered, use
  /// [isRegistered].
  /// {@endtemplate}
  T get<T extends Object>([DependencyKey? key]) {
    final dependency = _tryGetDependency<T>(key);
    if (dependency == null) {
      throw ArgumentError('Value with key $T has not been registered');
    }
    final value = dependency.tryResolve();
    if (value == null) {
      throw StateError('Value with key $T has not been resolved');
    }
    return value;
  }

  /// Returns the dependency if it's already resolved, otherwise returns null.
  /// If the dependency is not registered, throws an [ArgumentError].
  /// To see if a dependency is registered, use [isRegistered].
  T? tryGet<T extends Object>() {
    final dependency = _tryGetDependency<T>();
    if (dependency == null) {
      throw ArgumentError('Value with key $T has not been registered');
    }
    return dependency.tryResolve();
  }

  T? _tryResolveValue<T extends Object>([DependencyKey? key]) {
    final dependency = _tryGetDependency<T>(key);
    return dependency?.tryResolve();
  }

  /// Observe changes to a dependency. For watching multiple dependencies at
  /// once see extensions [observe2], [observe3] etc.
  ///
  /// When [observeState] is `false` (the default), this stream only emits
  /// when the dependency itself is (re-)registered, i.e. when [Deps.add] or
  /// [Deps.replace] installs a new value under this key - it won't emit if
  /// a value that happens to be a `ChangeNotifier`/`Listenable` fires its own
  /// internal notifications.
  ///
  /// When [observeState] is `true`, this stream also emits whenever the
  /// resolved value's [DependencyObserver] (see [Dependency.createObserver])
  /// reports such an internal state change. Internal state changes are
  /// delivered by subscribing directly to the backing [ManagedDependency]'s
  /// own stream (shared by every subscriber of this key), not by broadcasting
  /// through every dependency's shared event stream - so watching this key
  /// doesn't cost anything when an unrelated dependency's state changes.
  Stream<T> observe<T extends Object>({
    DependencyKey? key,
    bool observeState = false,
  }) {
    final effectiveKey = key ?? T;

    // Emits (with no payload) whenever the ManagedDependency backing this key
    // might have appeared, been replaced, or moved - i.e. registration
    // events, not internal state changes. These are rare compared to state
    // changes, so it's fine for every subscriber to filter this shared
    // stream individually.
    Stream<void> registrations() async* {
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

    if (!observeState) {
      return registrations().expand((_) sync* {
        final value = _tryResolveValue<T>(key);
        if (value != null) {
          yield value;
        }
      });
    }

    return _switchToLatest(registrations(), () => _tryGetDependency<T>(key)?.watch());
  }

  /// Equivalent to `triggers.switchMap((_) => resolve() ?? Stream.empty())`,
  /// hand-rolled to avoid rxdart's switchMap overhead - re-registration
  /// (what [triggers] fires on) is rare, so a plain callback-based resubscribe
  /// is cheaper than a full operator per subscriber.
  static Stream<T> _switchToLatest<T extends Object>(
    Stream<void> triggers,
    Stream<T>? Function() resolve,
  ) {
    late final StreamController<T> controller;
    StreamSubscription<void>? triggerSub;
    StreamSubscription<T>? innerSub;

    void resubscribe() {
      unawaited(innerSub?.cancel());
      innerSub = resolve()?.listen(controller.add, onError: controller.addError);
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
    _parentSubscription?.cancel();
    for (final value in _values.values) {
      unawaited(value.dispose());
    }
    return super.dispose();
  }
}

extension DepsObserveMany on Deps {
  Stream<List<Object>> observeMany(List<Type> types) => Rx.combineLatest(
        types.map((type) => observe(key: type)),
        (values) => values,
      );

  Stream<(A, B)> observe2<A, B>() =>
      observeMany([A, B]).map((list) => (list[0] as A, list[1] as B));

  Stream<(A, B, C)> observe3<A, B, C>() => observeMany([A, B, C])
      .map((list) => (list[0] as A, list[1] as B, list[2] as C));

  Stream<(A, B, C, D)> observe4<A, B, C, D>() => observeMany([A, B, C, D])
      .map((list) => (list[0] as A, list[1] as B, list[2] as C, list[3] as D));

  Stream<(A, B, C, D, E)> observe5<A, B, C, D, E>() =>
      observeMany([A, B, C, D, E]).map(
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
  /// observes this key with `observeState: true` - see [Deps.observe] and
  /// [watch]. Created lazily, on the first call to [watch], so a dependency
  /// that's only ever plain-read via [Deps.get] - the common "just a service
  /// locator" case - never pays for a [DependencyObserver] or a
  /// [BehaviorSubject] it doesn't need.
  BehaviorSubject<T>? _controller;
  StreamSubscription<void>? _observeSubscription;
  T? _currentValue;

  /// One observer for the current [_currentValue], not one per subscriber -
  /// see [DependencyObserver]. Only created once [watch] has been called at
  /// least once (see [_controller]); recreated whenever [_currentValue]
  /// itself is replaced (either by re-registration or by the
  /// [Dependency.update] chain below).
  DependencyObserver<T>? _stateObserver;
  bool _debugCreateCalled = false;
  bool _isDisposed = false;

  /// No-op unless [watch] has already been called at least once for this
  /// dependency - see [_controller].
  void _attachStateObserverIfWatched(T value) {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    _stateObserver = dependency.createObserver(value)
      ?..attach(() => controller.add(value));
  }

  void _ensureInitialized() {
    if (_isDisposed) {
      throw StateError('Dependency is disposed');
    }
    if (_currentValue != null) {
      return;
    }
    if (_debugCreateCalled) {
      throw StateError('Possibly encountered a cycle when creating dependency');
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
          .observeMany(observe)
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
          _attachStateObserverIfWatched(newValue);
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

  Stream<T> watch() {
    _ensureInitialized();
    var controller = _controller;
    if (controller == null) {
      controller = _controller = BehaviorSubject<T>();
      _attachStateObserverIfWatched(_currentValue!);
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
/// value, not one per subscriber to [Deps.observe]; call
/// [notifyStateChanged] whenever the observed value's state changes and
/// every current `observeState: true` subscriber for this key is notified.
abstract class DependencyObserver<T extends Object> {
  void Function()? _onChanged;

  /// Wires this observer up to its owning [ManagedDependency]. Called by the
  /// framework right after construction - implementers should not call this.
  @internal
  void attach(void Function() onChanged) {
    _onChanged = onChanged;
  }

  /// Call this whenever the observed value's internal state changes, to
  /// notify anyone observing this dependency via [Deps.observe] with
  /// `observeState: true` - without needing to know about [Deps] or
  /// [ManagedDependency] directly.
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
