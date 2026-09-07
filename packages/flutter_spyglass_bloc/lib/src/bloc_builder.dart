import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';

/// Signature for the `builder` function which takes the `BuildContext` along
/// with the `state` and is responsible for returning a widget which is to be
/// rendered. This is analogous to the `builder` function in [StreamBuilder].
typedef BlocWidgetBuilder<TState> = Widget Function(
    BuildContext context, TState state);

/// Signature for the `buildWhen` function which takes the previous `state`
/// and the current `state` and is responsible for returning a [bool] which
/// determines whether to rebuild [BlocBuilder]/[BlocConsumer] with the
/// current `state`.
typedef BlocBuilderCondition<TState> = bool Function(
    TState previous, TState current);

/// The flutter_spyglass counterpart to flutter_bloc's `BlocBuilder`.
///
/// Resolves a [TBloc] from the nearest [Deps] scope (via [BuildContext.get])
/// - or uses the one passed explicitly through [bloc] - and rebuilds
/// [builder] whenever the bloc emits a new state, subject to [buildWhen].
///
/// Unlike [BuildContext.watch], which rebuilds on every emission from the
/// bloc registered under [TBloc], this only rebuilds when [buildWhen]
/// (default: always) says the new state warrants it, and passes the state
/// itself to [builder] rather than the bloc.
class BlocBuilder<TBloc extends BlocBase<TState>, TState>
    extends StatefulWidget {
  /// See the class-level docs above.
  const BlocBuilder({
    super.key,
    required this.builder,
    this.bloc,
    this.buildWhen,
  });

  /// The bloc to build against. Defaults to `context.get<TBloc>()` - the
  /// nearest [TBloc] registered in the [Deps] scope.
  final TBloc? bloc;

  /// Builds the widget from the bloc's current/latest state.
  final BlocWidgetBuilder<TState> builder;

  /// Called with the previous and current state on every emission; the
  /// widget only rebuilds when this returns `true`. Defaults to rebuilding
  /// on every emission.
  final BlocBuilderCondition<TState>? buildWhen;

  @override
  State<BlocBuilder<TBloc, TState>> createState() =>
      _BlocBuilderState<TBloc, TState>();
}

class _BlocBuilderState<TBloc extends BlocBase<TState>, TState>
    extends State<BlocBuilder<TBloc, TState>> {
  late TBloc _bloc;
  late TState _state;
  StreamSubscription<TState>? _subscription;

  @override
  void initState() {
    super.initState();
    _bloc = widget.bloc ?? context.get<TBloc>();
    _state = _bloc.state;
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant BlocBuilder<TBloc, TState> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldBloc = oldWidget.bloc ?? _bloc;
    final currentBloc = widget.bloc ?? oldBloc;
    if (oldBloc != currentBloc) {
      _resubscribeTo(currentBloc);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bloc == null) {
      // Rebuild this element - and re-resolve _bloc below - whenever a new
      // instance gets registered under TBloc, without reacting to that
      // instance's own state changes; those are handled by _subscription.
      final currentBloc = context.watchInstance<TBloc>();
      if (currentBloc != _bloc) {
        _resubscribeTo(currentBloc);
      }
    }
    return widget.builder(context, _state);
  }

  void _resubscribeTo(TBloc bloc) {
    _subscription?.cancel();
    _bloc = bloc;
    _state = bloc.state;
    _subscribe();
  }

  void _subscribe() {
    _subscription = _bloc.stream.listen((state) {
      if (widget.buildWhen?.call(_state, state) ?? true) {
        setState(() => _state = state);
      } else {
        _state = state;
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
