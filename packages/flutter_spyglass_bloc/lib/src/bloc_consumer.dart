import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';

import 'bloc_builder.dart';
import 'bloc_listener.dart';

/// The flutter_spyglass counterpart to flutter_bloc's `BlocConsumer`.
///
/// Combines [BlocBuilder] and [BlocListener] - rebuilding with [builder] and
/// invoking [listener] in response to the same state changes - without
/// nesting the two widgets. Use it only when both a rebuild and a side
/// effect (navigation, a `SnackBar`, ...) are needed for the same state
/// change; otherwise prefer [BlocBuilder] or [BlocListener] alone.
class BlocConsumer<TBloc extends BlocBase<TState>, TState>
    extends StatefulWidget {
  const BlocConsumer({
    super.key,
    required this.builder,
    required this.listener,
    this.bloc,
    this.buildWhen,
    this.listenWhen,
  });

  /// The bloc to build against and listen to. Defaults to
  /// `context.get<TBloc>()` - the nearest [TBloc] registered in the [Deps]
  /// scope.
  final TBloc? bloc;

  final BlocWidgetBuilder<TState> builder;

  final BlocWidgetListener<TState> listener;

  /// See [BlocBuilder.buildWhen].
  final BlocBuilderCondition<TState>? buildWhen;

  /// See [BlocListener.listenWhen].
  final BlocListenerCondition<TState>? listenWhen;

  @override
  State<BlocConsumer<TBloc, TState>> createState() =>
      _BlocConsumerState<TBloc, TState>();
}

class _BlocConsumerState<TBloc extends BlocBase<TState>, TState>
    extends State<BlocConsumer<TBloc, TState>> {
  late TBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = widget.bloc ?? context.get<TBloc>();
  }

  @override
  void didUpdateWidget(covariant BlocConsumer<TBloc, TState> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldBloc = oldWidget.bloc ?? _bloc;
    final currentBloc = widget.bloc ?? oldBloc;
    if (oldBloc != currentBloc) {
      _bloc = currentBloc;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bloc == null) {
      // Rebuild this element - and re-resolve _bloc below - whenever a new
      // instance gets registered under TBloc; BlocBuilder below reacts to
      // that instance's own state changes on its own.
      final currentBloc = context.watchInstance<TBloc>();
      if (currentBloc != _bloc) {
        _bloc = currentBloc;
      }
    }
    return BlocBuilder<TBloc, TState>(
      bloc: _bloc,
      builder: widget.builder,
      buildWhen: (previous, current) {
        if (widget.listenWhen?.call(previous, current) ?? true) {
          widget.listener(context, current);
        }
        return widget.buildWhen?.call(previous, current) ?? true;
      },
    );
  }
}
