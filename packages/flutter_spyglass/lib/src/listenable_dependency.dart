import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:spyglass/spyglass.dart';

class ListenableDependency<T extends Listenable> extends Dependency<T> {
  const ListenableDependency(
    super.create, {
    super.debugLabel,
    super.dispose,
    super.observe,
    super.tags,
    super.update,
  });

  @override
  DependencyObserver<T> createObserver(T value) =>
      ListenableDependencyObserver(value);
}

class ListenableDependencyObserver<T extends Listenable>
    extends DependencyObserver<T> {
  ListenableDependencyObserver(this.listenable) {
    listenable.addListener(_listener);
  }
  final T listenable;

  void _listener() => notifyStateChanged();

  @override
  Future<void> dispose() async {
    listenable.removeListener(_listener);
  }
}

class ChangeNotifierDependency<T extends ChangeNotifier>
    extends ListenableDependency<T> {
  const ChangeNotifierDependency(
    super.create, {
    super.debugLabel,
    super.observe,
    super.tags,
    super.update,
    FutureOr<void> Function(T value)? dispose,
  }) : super(dispose: dispose ?? _dispose);

  static void _dispose(ChangeNotifier value) {
    value.dispose();
  }
}
