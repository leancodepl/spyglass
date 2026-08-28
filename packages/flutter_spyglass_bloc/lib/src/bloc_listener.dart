import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';

/// Signature for the `listener` function which takes the `BuildContext`
/// along with the `state` and is responsible for executing in response to
/// `state` changes.
typedef BlocWidgetListener<TState> = void Function(
    BuildContext context, TState state);

/// Signature for the `listenWhen` function which takes the previous `state`
/// and the current `state` and is responsible for returning a [bool] which
/// determines whether to call [BlocWidgetListener] of
/// [BlocListener]/[BlocConsumer] with the current `state`.
typedef BlocListenerCondition<TState> = bool Function(
    TState previous, TState current);

/// The flutter_spyglass counterpart to flutter_bloc's `BlocListener`.
///
/// Resolves a [TBloc] from the nearest [Deps] scope (via [BuildContext.get])
/// - or uses the one passed explicitly through [bloc] - and invokes
/// [listener] once for every state it emits, subject to [listenWhen]. Unlike
/// [BlocBuilder], [listener] never triggers a rebuild - use it for one-off
/// side effects such as navigation or showing a `SnackBar`.
class BlocListener<TBloc extends BlocBase<TState>, TState>
    extends StatefulWidget {
  const BlocListener({
    super.key,
    required this.listener,
    required this.child,
    this.bloc,
    this.listenWhen,
  });

  /// The bloc to listen to. Defaults to `context.get<TBloc>()` - the nearest
  /// [TBloc] registered in the [Deps] scope.
  final TBloc? bloc;

  final BlocWidgetListener<TState> listener;

  /// Called with the previous and current state on every emission;
  /// [listener] is only invoked when this returns `true`. Defaults to
  /// invoking [listener] on every emission.
  final BlocListenerCondition<TState>? listenWhen;

  final Widget child;

  @override
  State<BlocListener<TBloc, TState>> createState() =>
      _BlocListenerState<TBloc, TState>();
}

class _BlocListenerState<TBloc extends BlocBase<TState>, TState>
    extends State<BlocListener<TBloc, TState>> {
  late TBloc _bloc;
  late TState _previousState;
  StreamSubscription<TState>? _subscription;

  @override
  void initState() {
    super.initState();
    _bloc = widget.bloc ?? context.get<TBloc>();
    _previousState = _bloc.state;
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant BlocListener<TBloc, TState> oldWidget) {
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
    return widget.child;
  }

  void _resubscribeTo(TBloc bloc) {
    _subscription?.cancel();
    _bloc = bloc;
    _previousState = bloc.state;
    _subscribe();
  }

  void _subscribe() {
    _subscription = _bloc.stream.listen((state) {
      if (!mounted) return;
      if (widget.listenWhen?.call(_previousState, state) ?? true) {
        widget.listener(context, state);
      }
      _previousState = state;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
