import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rxdart/rxdart.dart';
import 'package:spyglass/spyglass.dart';

typedef Selector<T, R> = R Function(T value);

/// Obtain the nearest [Deps] scope.
Deps useDeps() {
  return DepsProvider.of(useContext());
}

/// Watch the specified dependency.
T useDependency<T extends Object>() {
  final deps = useDeps();

  return useStream(deps.observe<T>(), initialData: deps.get<T>()).requireData;
}

/// Register dependencies on mount; Unregister on unmount. What [DepsProvider]
/// does with its [DepsProvider.register] prop but in a hook form.
void useRegisterDeps(
  List<Dependency<Object>> dependencies, [
  List<Object?>? keys,
]) {
  final deps = useDeps();

  useEffect(
    () {
      final unregister = deps.addMany(dependencies);
      return unregister;
    },
    keys ?? dependencies.map((e) => e.key).toList(),
  );
}

/// Shortcuts for obtaining Deps values from BuildContext.
extension DepsContext on BuildContext {
  /// Obtain the nearest [Deps] scope.
  Deps get deps => DepsProvider.of(this);

  /// Read the value of a dependency without listening to changes.
  T get<T extends Object>() => deps.get<T>();

  /// Watch the value of a dependency and rebuild the widget when it changes.
  T observe<T extends Object>({bool observeState = true}) =>
      DepsProvider.observe<T>(this, observeState: observeState);

  T? maybeObserve<T extends Object>({bool observeState = true}) =>
      DepsProvider.maybeObserve<T>(this, observeState: observeState);

  R select<T extends Object, R>(Selector<T, R> selector) =>
      DepsProvider.select<T, R>(this, selector);

  R? maybeSelect<T extends Object, R>(Selector<T, R> selector) =>
      DepsProvider.maybeSelect<T, R>(this, selector);
}

/// Register on mount;  Unregister on unmount.
class DepsProvider extends HookWidget {
  const DepsProvider({
    super.key,
    this.deps,
    this.register,
    this.introduceScope = true,
    this.child,
    this.builder,
  }) : assert(child != null || builder != null);

  /// Provide a custom [Deps] instance that dependencies listed in [register]
  /// should be added to. This will also influence the provided scope to the
  /// [child]/[builder] by [DepsProvider.of] and [DepsProvider.observe].
  final Deps? deps;

  /// A list of dependencies to register on mount and unregister on unmount.
  /// These dependencies will be bound to this widget, effectively.
  final Iterable<Dependency<Object>>? register;

  /// By default [DepsProvider] introduces a new scope. Set this to `false` to
  /// just register new dependencies in [register].
  final bool introduceScope;

  /// The widget below this widget in the tree. Use [builder] alternatively.
  /// If you're going to read the deps in the child widget, you should use
  /// [builder] or [Builder] instead to avoid reading stale context.
  final Widget? child;

  /// Alternative to [child]. A function that builds the child widget.
  final TransitionBuilder? builder;

  /// Obtain the nearest [Deps] scope.
  static Deps of(BuildContext context) {
    return context.getInheritedWidgetOfExactType<_DepsInherited>()?.deps ??
        globalDeps;
  }

  /// Observe the value of a dependency specified by [T].
  static T observe<T extends Object>(BuildContext context,
      {bool observeState = true}) {
    return context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(
            aspect: (T, _ObserveOptions(observeState: observeState)))!
        .deps
        .get<T>();
  }

  static T? maybeObserve<T extends Object>(BuildContext context,
      {bool observeState = true}) {
    final deps = context.dependOnInheritedWidgetOfExactType<_DepsInherited>(
        aspect: (T, _ObserveOptions(observeState: observeState)))!.deps;
    if (deps.isRegistered<T>()) {
      return deps.tryGet<T>();
    } else {
      return null;
    }
  }

  static R select<T extends Object, R>(
      BuildContext context, Selector<T, R> selector) {
    final value = context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(aspect: (
          T,
          _ObserveOptions(observeState: true, selector: selector)
        ))!
        .deps
        .get<T>();
    return selector(value);
  }

  static R? maybeSelect<T extends Object, R>(
      BuildContext context, Selector<T, R> selector) {
    final deps = context.dependOnInheritedWidgetOfExactType<_DepsInherited>(
        aspect: (
          T,
          _ObserveOptions(observeState: true, selector: selector)
        ))!.deps;
    if (!deps.isRegistered<T>()) {
      return null;
    }
    final value = deps.tryGet<T>();
    return value != null ? selector(value) : null;
  }

  @override
  Widget build(BuildContext context) {
    final parentScope = of(context);
    // 1. Use deps from props
    // 2a. If should introduce new scope fork parent scope
    // 2b. Otherwise use parent scope
    final deps = useMemoized(
      () => this.deps ?? (introduceScope ? parentScope.fork() : parentScope),
      [
        this.deps,
        parentScope,
      ],
    );
    useEffect(
      () {
        if (introduceScope && this.deps == null) {
          return deps.dispose;
        }
        return null;
      },
      [deps, introduceScope, this.deps],
    );

    final register = this.register;

    useEffect(
      () {
        if (register == null) {
          return null;
        }

        final unregister = deps.addMany(register);

        return unregister;
      },
      [deps, ...?register?.map((e) => e.key)],
    );

    return _DepsInherited(
      deps: deps,
      child: Builder(
        builder: (context) {
          var result = child;
          if (builder case final builder?) {
            result = builder(context, result);
          }
          return result ?? const SizedBox();
        },
      ),
    );
  }
}

class _DepsInherited extends InheritedWidget {
  const _DepsInherited({
    required super.child,
    required this.deps,
  });

  final Deps deps;

  @override
  bool updateShouldNotify(_DepsInherited oldWidget) {
    return deps != oldWidget.deps;
  }

  @override
  InheritedElement createElement() {
    return _DepsElement(this);
  }
}

class _DepsElement extends InheritedElement {
  _DepsElement(_DepsInherited super.widget);

  @override
  _DepsInherited get widget => super.widget as _DepsInherited;

  final Map<(Element, Type), StreamSubscription<void>> _subscriptions = {};

  @override
  void updated(_DepsInherited oldWidget) {
    if (widget.deps != oldWidget.deps) {
      for (final sub in _subscriptions.values) {
        sub.cancel();
      }
      _subscriptions.clear();
    }
    super.updated(oldWidget);
  }

  @override
  void updateDependencies(Element dependent, Object? aspect) {
    setDependencies(dependent, aspect);
  }

  @override
  void setDependencies(Element dependent, Object? value) {
    if (value == null) {
      return;
    }
    if (value is! (Type, _ObserveOptions)) {
      throw ArgumentError.value(
          value, 'value', 'value must be a (Type, _ObserveOptions)');
    }
    final (type, options) = value;
    _subscriptions[(dependent, type)] ??= () {
      var stream =
          widget.deps.observe(key: type, observeState: options.observeState);
      if (options.selector case final selector?) {
        stream = stream
            .map((value) => (selector as dynamic)(value))
            .pairwise()
            .where((pair) => pair.first != pair.last);
      }
      return stream.listen((_) {
        dependent.markNeedsBuild();
      });
    }();
  }

  @override
  void removeDependent(Element dependent) {
    for (final key in _subscriptions.keys) {
      if (key.$1 == dependent) {
        _subscriptions[key]?.cancel();
        _subscriptions.remove(key);
      }
    }
    super.removeDependent(dependent);
  }

  @override
  void unmount() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    super.unmount();
  }
}

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
    implements DependencyObserver<T> {
  ListenableDependencyObserver(this.listenable) {
    listenable.addListener(_listener);
  }
  final T listenable;

  final StreamController<T> _controller = StreamController<T>.broadcast();

  void _listener() {
    _controller.add(listenable);
  }

  @override
  Future<void> dispose() {
    listenable.removeListener(_listener);
    return _controller.close();
  }

  @override
  Stream<T> listen() {
    return _controller.stream;
  }
}

@immutable
class _ObserveOptions {
  const _ObserveOptions({required this.observeState, this.selector});

  final bool observeState;
  final Function? selector;
}
