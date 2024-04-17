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
class Dependency<T extends Object> {
  /// An immutable object describing a dependency. It can be registered in [Deps]
  /// by using [Deps.add].
  const Dependency({
    required this.create,
    this.update,
    this.when,
    this.dispose,
    this.debugLabel,
  }) : assert(
          when != null || update == null,
          'when must be provided if update is provided',
        );

  /// An immutable object describing a dependency. It can be registered in [Deps]
  /// by using [Deps.add].
  ///
  /// This is a shorthand for creating a dependency that doesn't change
  /// over time and does not need to be lazily created.
  factory Dependency.value(T value) => Dependency(create: (_) => value);

  /// The key or type of the dependency. It is a unique identifier for the
  /// dependency in its [Deps].
  DependencyKey get key => T;

  /// Creates a new instance of [T]. You can use provided [Deps] to obtain
  /// required dependencies. This callback can be asynchronous to perform
  /// long running initialization or await another dependency.
  final FutureOr<T> Function(Deps deps) create;

  /// Updates or creates a new instance of the dependency in reaction to
  /// changes in other dependencies specified by [when].
  final T Function(Deps deps, T oldValue)? update;

  /// Use one of [Deps.watch], [DepsWatchMany.watch2] etc. to specify which
  /// changes you want to observe.
  final Stream<Object?> Function(Deps deps)? when;

  /// Perform actions to clean up after the object is no longer needed.

  final FutureOr<void> Function(T value)? dispose;

  /// A debug label to help identify the dependency in logs.
  final String? debugLabel;

  /// NOTE
  /// This method is required to retain generic type information when creating
  /// a [ManagedDependency] instance in e.g. [Deps.addMany]
  // ignore: comment_references
  /// and [DepsProvider.register] from flutter_spyglass.
  ManagedDependency<T> _toManaged(Deps deps) => ManagedDependency(this, deps);

  @override
  String toString() {
    return 'Dependency<$T>($debugLabel)';
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

  /// Peek at the value of a dependency without resolving it.
  T? peek<T extends Object>([DependencyKey? key]) =>
      switch (_tryGetDependency<T>(key)?._currentValue) {
        null => null,
        final T value => value,
        Future<T> _ => null,
      };

  /// Add or update a dependency.
  Unregister add<T extends Object>(Dependency<T> dependency) {
    final managed = dependency._toManaged(this);

    remove(managed.key);
    _values[managed.key] = managed;
    notify(DependencyRegistered(key: managed.key));
    return () => remove(managed.key);
  }

  /// Helper method for adding multiple dependencies at once if you find
  /// calling `deps..add()..add()...` too verbose.
  Unregister addMany(Iterable<Dependency<Object>> dependencies) {
    final unregisters = <Unregister>[];
    for (final dependency in dependencies) {
      final unregister = add(dependency);
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
  T get<T extends Object>() {
    final dependency = _tryGetDependency<T>();
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

  /// Returns a future that resolves when the specified dependency
  /// is initialized. If the dependency hasn't been registered yet,
  /// the future will still wait until it is.
  ///
  /// Note that this might be dangerous if the dependency is never registered.
  /// In this case the future will never resolve.
  Future<T> getAsync<T extends Object>([DependencyKey? key]) async {
    return watch<T>(key).first;
  }

  T? _tryResolveValue<T extends Object>([DependencyKey? key]) {
    final dependency = _tryGetDependency<T>(key);
    return dependency?.tryResolve();
  }

  /// Observe all changes to a dependency. For watching multiple dependencies
  /// at once see extensions [watch2], [watch3] etc.
  ///
  /// Note that this stream only emits when a new instance is registered, so
  /// if a dependency is a ChangeNotifier, Bloc, or similar, watch won't emit
  /// when its internal state changes.
  Stream<T> watch<T extends Object>([DependencyKey? key]) async* {
    final effectiveKey = key ?? T;
    final value = _tryResolveValue<T>(key);
    if (value != null) {
      yield value;
    }

    await for (final event in events) {
      final shouldYield = switch (event) {
        DependencyChanged(:final key) when key == effectiveKey => true,
        DependencyRegistered(:final key) when key == effectiveKey => true,
        _ => false,
      };

      if (shouldYield) {
        final value = _tryResolveValue<T>(key);
        if (value != null) {
          yield value;
        }
      }
    }
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
  Future<void> ensureResolved(Iterable<Type> types) async {
    await [
      for (final type in types) getAsync(type),
    ].wait;
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

extension DepsWatchMany on Deps {
  Stream<List<Object>> watchMany(List<Type> types) => Rx.combineLatest(
        types.map(watch),
        (values) => values,
      );

  Stream<(A, B)> watch2<A, B>() =>
      watchMany([A, B]).map((list) => (list[0] as A, list[1] as B));

  Stream<(A, B, C)> watch3<A, B, C>() => watchMany([A, B, C])
      .map((list) => (list[0] as A, list[1] as B, list[2] as C));

  Stream<(A, B, C, D)> watch4<A, B, C, D>() => watchMany([A, B, C, D])
      .map((list) => (list[0] as A, list[1] as B, list[2] as C, list[3] as D));

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

/// This class helps manage lifecycle of a single dependency. It is tightly
/// coupled with [Deps]. It's an internal structure and it should never be
/// exposed as part of the public API.
@internal
class ManagedDependency<T extends Object> {
  ManagedDependency(this.dependency, this.deps);

  final Dependency<T> dependency;
  final Deps deps;

  DependencyKey get key => dependency.key;

  final _controller = StreamController<T>.broadcast();
  StreamSubscription<Object?>? _whenSubscription;
  FutureOr<T>? _currentValue;
  bool _debugCreateCalled = false;
  bool _isDisposed = false;

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
    Future.sync(() async {
      _currentValue = await _currentValue!;
      // reason: ManagedDependency and Deps work in tandem
      // ignore: invalid_use_of_protected_member
      deps.notify(DependencyChanged(key: key));

      if ((dependency.when, dependency.update)
          case (final when_?, final update?)) {
        unawaited(_whenSubscription?.cancel());
        _whenSubscription = when_(deps)
            .map((_) => update(deps, _currentValue! as T))
            .listen((newValue) {
          if (newValue != _currentValue) {
            _currentValue = newValue;
            // reason: ManagedDependency and Deps work in tandem
            // ignore: invalid_use_of_protected_member
            deps.notify(DependencyChanged(key: key));
          }
        });
      }
    });
  }

  T resolve() {
    _ensureInitialized();
    return switch (_currentValue) {
      final T value => value,
      null => throw StateError('Initialization error. This is a bug.'),
      Future<T>() => throw StateError('Value has not been resolved yet'),
    };
  }

  T? tryResolve() {
    _ensureInitialized();
    return switch (_currentValue) {
      final T value => value,
      null => null,
      Future<T>() => null,
    };
  }

  Future<T> resolveAsync() async {
    _ensureInitialized();
    return switch (_currentValue) {
      final FutureOr<T> value => value,
      null => throw StateError('Initialization error. This is a bug.'),
    };
  }

  Stream<T> watch() {
    _ensureInitialized();
    return _controller.stream;
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _whenSubscription?.cancel();
    await _controller.close();
    if ((dependency.dispose, _currentValue)
        case (final dispose?, final value?)) {
      final resolvedValue = await value;
      await dispose(resolvedValue);
    }
  }
}
