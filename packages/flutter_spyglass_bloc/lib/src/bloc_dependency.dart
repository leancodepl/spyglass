import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';

/// Registers a `Bloc`/`Cubit` as a spyglass [Dependency]. The instance is
/// closed automatically on disposal - via [BlocBase.close] - unless [dispose]
/// is overridden, and any widget using `context.watch<TBloc>()` (or
// ignore: comment_references
/// [BlocBuilder]/[BlocListener]/[BlocConsumer]) rebuilds/reacts on every
/// emitted state.
class BlocDependency<TBloc extends BlocBase<dynamic>>
    extends Dependency<TBloc> {
  /// See the class-level docs above. Pass [dispose] to override the default
  /// `value.close()`.
  const BlocDependency(
    super.create, {
    super.debugLabel,
    super.tags,
    FutureOr<void> Function(TBloc value)? dispose,
  }) : super(dispose: dispose ?? _dispose);

  static Future<void> _dispose(BlocBase<dynamic> value) => value.close();

  @override
  DependencyObserver<TBloc> createObserver(TBloc value) {
    return BlocDependencyObserver(value);
  }

  @override
  String toString() {
    return 'BlocDependency<$TBloc>($debugLabel)';
  }
}

/// The [DependencyObserver] behind [BlocDependency] - relays [bloc]'s own
/// emissions to `Deps.watch` subscribers.
class BlocDependencyObserver<TBloc extends BlocBase<dynamic>>
    extends DependencyObserver<TBloc> {
  /// Starts listening to [bloc]'s stream immediately.
  BlocDependencyObserver(this.bloc) {
    _subscription = bloc.stream.listen((_) => notifyStateChanged());
  }

  /// The bloc/cubit being observed.
  final TBloc bloc;
  late final StreamSubscription<void> _subscription;

  @override
  Future<void> dispose() async {
    await _subscription.cancel();
  }
}
