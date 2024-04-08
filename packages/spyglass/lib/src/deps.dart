import 'dart:async';
import 'dart:async' as async;

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';
import 'package:spyglass/src/event_notifier.dart';

final _zoneKey = Object();
Deps get globalDeps => Zone.current[_zoneKey] as Deps? ?? Deps.root;

/// Alias for [globalDeps].
Deps get deps => globalDeps;

typedef DependencyKey = Type;

typedef Constructor<T> = FutureOr<T> Function(Deps deps);
typedef Watcher = Stream<Object> Function(Deps deps);
typedef Disposer<T> = FutureOr<void> Function(T object);
typedef Unregister = void Function();

sealed class DepsEvent {}

final class DependencyRegistered extends Equatable implements DepsEvent {
  const DependencyRegistered({
    required this.key,
  });

  final DependencyKey key;

  @override
  List<Object?> get props => [key];
}

final class DependencyUnregistered extends Equatable implements DepsEvent {
  const DependencyUnregistered({
    required this.key,
  });

  final DependencyKey key;

  @override
  List<Object?> get props => [key];
}

final class DependencyChanged extends Equatable implements DepsEvent {
  const DependencyChanged({
    required this.key,
  });

  final DependencyKey key;

  @override
  List<Object?> get props => [key];
}

enum DependencyState {
  initial,
  resolving,
  resolved,
  disposing,
  disposed,
}

class Dependency<T extends Object> {
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

  factory Dependency.value(T value) => Dependency(create: (_) => value);

  DependencyKey get key => T;
  final FutureOr<T> Function(Deps deps) create;
  final T Function(Deps deps, T oldValue)? update;
  final Stream<Object?> Function(Deps deps)? when;
  final FutureOr<void> Function(T value)? dispose;
  final String? debugLabel;

  /// NOTE
  /// This method is required to retain generic type information when creating
  /// a [ManagedDependency] instance in e.g. [Deps.addMany]
  /// and [DepsProvider.register] from flutter_spyglass.
  ManagedDependency<T> _toManaged(Deps deps) => ManagedDependency(this, deps);
}

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

  void _ensureInitialized() async {
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
    _currentValue = await _currentValue!;
    deps.notify(DependencyChanged(key: key));
    if ((dependency.when, dependency.update)
        case (final when_?, final update?)) {
      _whenSubscription?.cancel();
      _whenSubscription = when_(deps)
          .map((_) => update(deps, _currentValue as T))
          .listen((newValue) {
        if (newValue != _currentValue) {
          _currentValue = newValue;
          deps.notify(DependencyChanged(key: key));
        }
      });
    }
  }

  T resolve() {
    _ensureInitialized();
    return switch (_currentValue) {
      T value => value,
      null => throw StateError('Initialization error. This is a bug.'),
      Future<T>() => throw StateError('Value has not been resolved yet'),
    };
  }

  T? tryResolve() {
    _ensureInitialized();
    return switch (_currentValue) {
      T value => value,
      null => null,
      Future<T>() => null,
    };
  }

  Future<T> resolveAsync() async {
    _ensureInitialized();
    return switch (_currentValue) {
      FutureOr<T> value => value,
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
    _whenSubscription?.cancel();
    await _controller.close();
    if ((dependency.dispose, _currentValue)
        case (final dispose?, final value?)) {
      final resolvedValue = await value;
      await dispose(resolvedValue);
    }
  }
}

class Deps extends EventNotifier<DepsEvent> {
  /// Input [values] are copied.
  Deps._({
    required this.parent,
    Map<Object, ManagedDependency>? values,
  }) : _values = {...?values} {
    _setupParentSubscription();
  }

  void _setupParentSubscription() {
    _parentSubscription =
        parent?.events.where(_isNotShadowedEvent).listen(notify);
  }

  bool _isNotShadowedEvent(DepsEvent e) {
    // Events are shadowed when this scope already has the specified key.
    return switch (e) {
      DependencyRegistered(:final key) => !_isRegisteredHere(key),
      DependencyUnregistered(:final key) => !_isRegisteredHere(key),
      DependencyChanged(:final key) => !_isRegisteredHere(key),
    };
  }

  /// Creates a completely empty [Deps], detached from the [globalDeps] root
  /// ancestor.
  Deps.detached() : this._(parent: null);

  /// Returns the current global [Deps] instance. See also [globalDeps].
  factory Deps() => globalDeps;

  /// The root [Deps] instance. This is the ancestor of all other [Deps].
  /// Most likely this is the same as [globalDeps] unless you're using
  /// [Deps.runZoned].
  static final root = Deps.detached();

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
        T value => value,
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

  void clear() {
    for (final value in _values.values) {
      unawaited(Future.sync(() => value.dispose()));
    }
    _values.clear();
  }

  /// Checks whether a dependency with the given key is registered in this
  /// [Deps] or any of its ancestors.
  bool isRegistered<T>([Type? key]) {
    final effectiveKey = key ?? T;

    return scopeChain.any((scope) => scope._values.containsKey(effectiveKey));
  }

  bool _isRegisteredHere<T>([DependencyKey? key]) {
    final effectiveKey = key ?? T;

    return _values.containsKey(effectiveKey);
  }

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

  T call<T extends Object>() => get<T>();

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

  T? tryGet<T extends Object>() {
    final dependency = _tryGetDependency<T>();
    if (dependency == null) {
      throw ArgumentError('Value with key $T has not been registered');
    }
    return dependency.tryResolve();
  }

  Future<T> getAsync<T extends Object>() async {
    return watch<T>().first;
  }

  T? _tryResolveValue<T extends Object>([DependencyKey? key]) {
    final dependency = _tryGetDependency<T>(key);
    return dependency?.tryResolve();
  }

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

  @override
  Future<void> dispose() {
    _parentSubscription?.cancel();
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
      watchMany([A, B, C, D, E]).map((list) => (
            list[0] as A,
            list[1] as B,
            list[2] as C,
            list[3] as D,
            list[4] as E
          ));
}
