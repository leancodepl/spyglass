import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:spyglass/spyglass.dart';

/// A [Dependency] whose value is a [Listenable] - `deps.watch<T>()` (and
/// `context.watch<T>()`) reacts to [T] calling `notifyListeners()`, not just
/// to a new instance being registered. Not every `Listenable` is disposable,
/// so unlike [ChangeNotifierDependency] this has no default [dispose].
class ListenableDependency<T extends Listenable> extends Dependency<T> {
  /// See the class-level docs above.
  const ListenableDependency(
    super.create, {
    super.debugLabel,
    super.dispose,
    super.tags,
  });

  @override
  DependencyObserver<T> createObserver(T value) =>
      ListenableDependencyObserver(value);
}

/// The [DependencyObserver] behind [ListenableDependency] - relays
/// [listenable]'s own notifications to `Deps.watch` subscribers.
class ListenableDependencyObserver<T extends Listenable>
    extends DependencyObserver<T> {
  /// Starts listening to [listenable] immediately.
  ListenableDependencyObserver(this.listenable) {
    listenable.addListener(_listener);
  }

  /// The value being observed.
  final T listenable;

  void _listener() => notifyStateChanged();

  @override
  Future<void> dispose() async {
    listenable.removeListener(_listener);
  }
}

/// A [ListenableDependency] specialized for [ChangeNotifier]: unlike the
/// base class, this defaults [dispose] to calling `value.dispose()`, since
/// every `ChangeNotifier` supports that.
class ChangeNotifierDependency<T extends ChangeNotifier>
    extends ListenableDependency<T> {
  /// See the class-level docs above. Pass [dispose] to override the default
  /// `value.dispose()`.
  const ChangeNotifierDependency(
    super.create, {
    super.debugLabel,
    super.tags,
    FutureOr<void> Function(T value)? dispose,
  }) : super(dispose: dispose ?? _dispose);

  static void _dispose(ChangeNotifier value) {
    value.dispose();
  }
}
