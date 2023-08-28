import 'dart:async' as async;

import 'package:equatable/equatable.dart';
import 'package:spyglass/src/event_notifier.dart';

final _zoneKey = Object();

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
  })  : _create = create,
        _disposer = dispose,
        key = key ?? T;

  final Constructor<T> _create;
  final Disposer<T>? _disposer;
  final Object key;

  bool _debugCreateCalled = false;
  T? _value;

  T resolve(Deps scope) {
    final value = _value;
    if (value != null) {
      return value;
    }
    if (_debugCreateCalled) {
      throw StateError('Possibly encountered a cycle when creating dependency');
    }
    _debugCreateCalled = true;
    return _value = _create(scope);
  }

  Future<void> dispose() async {
    final value = _value;
    if (value != null) {
      return Future.sync(() => _disposer?.call(value));
    }
  }
}

typedef Constructor<T> = T Function(Deps scope);
typedef Disposer<T> = async.FutureOr<void> Function(T object);

Deps get globalDeps => async.Zone.current[_zoneKey] as Deps? ?? Deps.root;

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
    final effectiveKey = key ?? T;
    final value = _values.remove(effectiveKey);
    async.unawaited(value?.dispose());
  }

  void clear() {
    _values.clear();
  }

  bool contains<T>([Object? key]) {
    final effectiveKey = key ?? T;

    return _scopeChain.any((scope) => scope._values.containsKey(effectiveKey));
  }

  T get<T>([Object? key]) {
    final effectiveKey = key ?? T;
    for (final scope in _scopeChain) {
      final value = scope._values[effectiveKey];
      if (value != null) {
        return value.resolve(scope) as T;
      }
    }
    throw StateError('Value with key $effectiveKey has not been registered');
  }

  T? tryGet<T>([Object? key]) {
    try {
      return get<T>(key);
    } on StateError {
      return null;
    }
  }

  Stream<T> watch<T>([Object? key]) async* {
    final effectiveKey = key ?? T;
    if (contains(effectiveKey)) {
      yield get<T>(key);
    }
    await for (final event in events) {
      if (event case DependencyChanged event when event.key == effectiveKey) {
        yield get<T>(key);
      }
    }
  }

  @override
  async.Future<void> dispose() {
    _parentSubscription?.cancel();
    return super.dispose();
  }
}
