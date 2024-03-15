import 'dart:async' as async;
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:spyglass/src/event_notifier.dart';

final _zoneKey = Object();
Deps get globalDeps => async.Zone.current[_zoneKey] as Deps? ?? Deps.root;

sealed class DepsEvent {}

final class DependencyChanged extends Equatable implements DepsEvent {
  const DependencyChanged({
    required this.key,
    required this.fromParent,
  });

  final Object? key;
  final bool fromParent;

  @override
  List<Object?> get props => [key, fromParent];
}

class Dependency<T extends Object> {
  Dependency({
    required Constructor<T> create,
    Disposer<T>? dispose,
    Object? key,
    this.debugLabel,
  })  : _create = create,
        _disposer = dispose,
        key = DependencyKey<T>(key);

  final Constructor<T> _create;
  final Disposer<T>? _disposer;
  final DependencyKey<T> key;
  final String? debugLabel;

  bool _debugCreateCalled = false;
  FutureOr<T>? _value;

  bool get isResolved => _value != null && _value is T;

  T resolveNow(Deps scope) {
    unawaited(resolve(scope));
    if (_value case T value?) {
      return value;
    } else {
      throw StateError('Depenency is not yet initialized.');
    }
  }

  Future<T> resolve(Deps scope) async {
    if (_value case final value?) {
      return value;
    }
    if (_debugCreateCalled) {
      throw StateError('Possibly encountered a cycle when creating dependency');
    }
    _debugCreateCalled = true;
    return _value = await (_value = _create(scope));
  }

  Future<void> dispose() async {
    if (_value case final value?) {
      _disposer?.call(await value);
    }
  }

  @override
  String toString() {
    return 'Dependency<$T>(label: $debugLabel, key: $key)';
  }
}

typedef Constructor<T> = FutureOr<T> Function(Deps scope);
typedef Disposer<T> = async.FutureOr<void> Function(T object);

class Deps extends EventNotifier<DepsEvent> {
  Deps._({
    required this.parent,
    Map<Object, Dependency>? values,
  }) : _values = values ?? {} {
    _parentSubscription = parent?.events.listen((event) {
      switch (event) {
        case DependencyChanged(:final key):
          notify(DependencyChanged(
            key: key,
            fromParent: true,
          ));
          break;
      }
    });
  }

  Deps.detached() : this._(parent: null);

  factory Deps() => globalDeps;

  static final root = Deps.detached();

  Deps fork() => Deps._(parent: this);

  Deps copy() => Deps._(
        parent: parent,
        values: {..._values},
      );

  Deps flattened() => Deps._(
        parent: parent,
        values: {
          for (final scope in _scopeChain.toList().reversed) ...scope._values,
        },
      );

  Deps detached() => Deps._(
        parent: null,
        values: {..._values},
      );

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
  async.StreamSubscription<void>? _parentSubscription;

  final Map<Object, Dependency> _values;

  Iterable<Deps> get _scopeChain sync* {
    Deps? scope = this;
    while (scope != null) {
      yield scope;
      scope = scope.parent;
    }
  }

  Iterable<Dependency<Object>> get entries => _values.values;

  void Function() register<T extends Object>(Dependency<T> dependency) {
    unregister(dependency.key);
    _values[dependency.key] = dependency;
    notify(DependencyChanged(
      key: dependency.key,
      fromParent: false,
    ));
    return () => unregister(dependency.key);
  }

  void unregister<T extends Object>([Object? key]) {
    final effectiveKey = DependencyKey<T>(key);
    final value = _values.remove(effectiveKey);
    async.unawaited(value?.dispose());
  }

  void clear() {
    for (final value in _values.values) {
      async.unawaited(value.dispose());
    }
    _values.clear();
  }

  bool contains<T>([Object? key]) {
    final effectiveKey = DependencyKey<T>(key);

    return _scopeChain.any((scope) => scope._values.containsKey(effectiveKey));
  }

  Dependency<T>? _tryGetDependency<T extends Object>([Object? key]) {
    final effectiveKey = DependencyKey<T>(key);
    for (final scope in _scopeChain) {
      final value = scope._values[effectiveKey];
      if (value != null && value is Dependency<T>) {
        return value;
      }
    }
    return null;
  }

  T get<T extends Object>([Object? key]) {
    final dependency = _tryGetDependency<T>(key);
    if (dependency == null) {
      final effectiveKey = DependencyKey<T>(key);
      throw ArgumentError(
          'Value with key $effectiveKey has not been registered');
    }
    return dependency.resolveNow(this);
  }

  T? tryGet<T extends Object>([Object? key]) {
    final dependency = _tryGetDependency<T>(key);
    if (dependency != null && dependency.isResolved) {
      return dependency.resolveNow(this);
    } else {
      return null;
    }
  }

  Future<T> getLater<T extends Object>([Object? key]) async {
    return watch<T>(key).first;
  }

  Stream<T> watch<T extends Object>([Object? key]) async* {
    final effectiveKey = DependencyKey<T>(key);
    final dependency = _tryGetDependency<T>(key);
    if (dependency != null) {
      final x = await dependency.resolve(this);
      yield x;
    }
    await for (final event in events) {
      if (event is DependencyChanged && event.key == effectiveKey) {
        final dependency = _tryGetDependency<T>(key);
        if (dependency != null) {
          yield await dependency.resolve(this);
        }
      }
    }
  }

  @override
  async.Future<void> dispose() {
    _parentSubscription?.cancel();
    return super.dispose();
  }
}

class DependencyKey<T> extends Equatable {
  const DependencyKey([this.value]);

  final Object? value;

  @override
  List<Object?> get props => [value];
}
