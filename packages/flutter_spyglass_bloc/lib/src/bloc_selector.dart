import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';

import 'bloc_builder.dart';

/// Signature for the `selector` function which takes the `state` and is
/// responsible for returning the selected value that a [BlocSelector]
/// rebuilds on changes of.
typedef BlocWidgetSelector<TState, TSelected> =
    TSelected Function(TState state);

/// The flutter_spyglass counterpart to flutter_bloc's `BlocSelector`.
///
// ignore: comment_references
/// Resolves a [TBloc] from the nearest [Deps] scope (via [BuildContext.get])
/// - or uses the one passed explicitly through [bloc] - and rebuilds
/// [builder] only when [selector] returns a value that differs (via `!=`)
/// from the previously selected one.
///
/// Prefer this over [BlocBuilder] with a manual `buildWhen` when only part of
/// the state matters for the rebuild.
class BlocSelector<TBloc extends BlocBase<TState>, TState, TSelected>
    extends StatefulWidget {
  /// See the class-level docs above.
  const BlocSelector({
    super.key,
    required this.selector,
    required this.builder,
    this.bloc,
  });

  /// The bloc to build against. Defaults to `context.get<TBloc>()` - the
  /// nearest [TBloc] registered in the [Deps] scope.
  final TBloc? bloc;

  /// Returns the value that this widget rebuilds on changes of.
  // ignore: unsafe_variance
  final BlocWidgetSelector<TState, TSelected> selector;

  /// Builds the widget from the currently selected value.
  // ignore: unsafe_variance
  final BlocWidgetBuilder<TSelected> builder;

  @override
  State<BlocSelector<TBloc, TState, TSelected>> createState() =>
      _BlocSelectorState<TBloc, TState, TSelected>();
}

class _BlocSelectorState<TBloc extends BlocBase<TState>, TState, TSelected>
    extends State<BlocSelector<TBloc, TState, TSelected>> {
  late TBloc _bloc;
  late TSelected _selected;
  StreamSubscription<TState>? _subscription;

  @override
  void initState() {
    super.initState();
    _bloc = widget.bloc ?? context.get<TBloc>();
    _selected = widget.selector(_bloc.state);
    _subscribe();
  }

  @override
  void didUpdateWidget(
    covariant BlocSelector<TBloc, TState, TSelected> oldWidget,
  ) {
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
    return widget.builder(context, _selected);
  }

  void _resubscribeTo(TBloc bloc) {
    _subscription?.cancel();
    _bloc = bloc;
    _selected = widget.selector(bloc.state);
    _subscribe();
  }

  void _subscribe() {
    _subscription = _bloc.stream.listen((state) {
      final selected = widget.selector(state);
      if (selected != _selected) {
        setState(() => _selected = selected);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
