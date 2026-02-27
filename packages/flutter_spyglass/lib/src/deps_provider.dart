import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:spyglass/spyglass.dart';

/// Obtain the nearest [Deps] scope.
Deps useDeps() {
  return DepsProvider.of(useContext());
}

/// Watch the specified dependency.
T useDependency<T extends Object>() {
  final deps = useDeps();

  return useStream(deps.watch<T>(), initialData: deps.get<T>()).requireData;
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
  T watch<T extends Object>() => DepsProvider.watch<T>(this);

  T? maybeWatch<T extends Object>() => DepsProvider.maybeWatch<T>(this);
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
  /// [child]/[builder] by [DepsProvider.of] and [DepsProvider.watch].
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
    return context.dependOnInheritedWidgetOfExactType<_DepsInherited>()?.deps ??
        globalDeps;
  }

  /// Observe the value of a dependency specified by [T].
  static T watch<T extends Object>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(aspect: T)!
        .deps
        .get<T>();
  }

  static T? maybeWatch<T extends Object>(BuildContext context) {
    final deps = context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(aspect: T)!
        .deps;
    if (deps.isRegistered<T>()) {
      return deps.tryGet<T>();
    } else {
      return null;
    }
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
      for (final MapEntry(:key, value: sub) in _subscriptions.entries) {
        sub.cancel();
        _subscriptions[key] = widget.deps.watch(key.$2).listen((e) {
          key.$1.didChangeDependencies();
        });
      }
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
    if (value is! Type) {
      throw ArgumentError.value(value, 'value', 'value must be a Type');
    }
    _subscriptions[(dependent, value)]?.cancel();
    _subscriptions[(dependent, value)] = widget.deps.watch(value).listen((e) {
      dependent.markNeedsBuild();
    });
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
    super.unmount();
  }
}
