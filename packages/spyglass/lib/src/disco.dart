import 'package:meta/meta.dart';

class DiscoDep<T> {
  DiscoDep(
    this.create, {
    required this.key,
    Future<void>? Function(T value)? dispose,
    this.debugLabel,
  }) : disposeFn = dispose;

  final Object key;
  final T Function() create;
  final Future<void>? Function(T value)? disposeFn;
  final String? debugLabel;

  bool debugCreateCalled = false;

  T? _value;

  T call() {
    if (_value case final value?) {
      return value;
    }
    if (debugCreateCalled) {
      throw StateError(
          'Possibly encountered a cycle when creating dependency of type $T ($debugLabel)');
    }
    debugCreateCalled = true;
    return _value = create();
  }

  Future<void> dispose() async {
    if (_value case final value?) {
      await disposeFn?.call(value);
    }
  }
}

abstract class DiscoScope {
  DiscoScope({
    this.parent,
  });

  final DiscoScope? parent;

  final Map<Object, DiscoDep<dynamic>> _dependencies = {};

  DiscoDep<T> singleton<T, TScope extends DiscoScope>(DiscoDep<T> dep) {
    if (TScope == runtimeType) {
      return _dependencies.putIfAbsent(dep.key, () => dep) as DiscoDep<T>;
    } else {
      return parent!.singleton<T, TScope>(dep);
    }
  }

  DiscoDep<T> interface<T, TScope extends DiscoScope>(
    DiscoDep<T> impl, {
    required Object key,
    String? debugLabel,
  }) {
    if (TScope == runtimeType) {
      return _dependencies.putIfAbsent(key,
              () => DiscoDep(() => impl(), key: key, debugLabel: debugLabel))
          as DiscoDep<T>;
    } else {
      return parent!
          .interface<T, TScope>(impl, key: key, debugLabel: debugLabel);
    }
  }

  @protected
  DiscoDep<T> get<T>(Object key) {
    return _dependencies[key] as DiscoDep<T>? ?? parent!.get<T>(key);
  }

  Future<void> dispose() async {
    await [for (final dep in _dependencies.values) dep.dispose()].wait;
  }
}
