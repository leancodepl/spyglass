import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';

typedef BlocWidgetBuilder<TState> = Widget Function(
    BuildContext context, TState state);

class BlocDependency<TBloc extends BlocBase> extends Dependency<TBloc> {
  const BlocDependency(
    super.create, {
    super.debugLabel,
    super.dispose,
    super.observe,
    super.tags,
    super.update,
  });

  @override
  DependencyObserver<TBloc> createObserver(TBloc value) {
    return BlocDependencyObserver(value);
  }

  @override
  String toString() {
    return 'BlocDependency<$TBloc>($debugLabel)';
  }
}

class BlocDependencyObserver<TBloc extends BlocBase>
    implements DependencyObserver<TBloc> {
  BlocDependencyObserver(this.bloc);

  final TBloc bloc;

  @override
  Stream<TBloc> listen() {
    return bloc.stream.map((_) => bloc);
  }

  @override
  Future<void> dispose() async {
    // no-op
  }
}
