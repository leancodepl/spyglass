import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:spyglass/spyglass.dart';

/// Obtain the nearest [Deps] scope.
Deps useDeps() {
  return DepsProvider.of(useContext());
}

/// Watch the specified dependency.
T useDependency<T extends Object>() {
  final context = useContext();
  final deps = DepsProvider.of(context);
  return useStream(deps.watch<T>(), initialData: deps.get<T>()).requireData;
}

/// Register dependencies on mount; Unregister on unmount. What [DepsProvider]
/// does with its [DepsProvider.register] prop but in a hook form.
void useRegisterDeps(
  List<Dependency<Object>> dependencies, [
  List<Object?> keys = const [],
]) {
  final context = useContext();
  final deps = DepsProvider.of(context);
  useEffect(
    () {
      final unregister = deps.addMany(dependencies);
      return unregister;
    },
    keys,
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
    return InheritedModel.inheritFrom<_DepsInherited>(
          context,
        )?.deps ??
        globalDeps;
  }

  /// Observe the value of a dependency specified by [T].
  ///
  /// Note: Current implementation using InheritedModel/InheritedWidget
  /// might be prone to performance issues. This API might change in the future
  /// in favor of hooks.
  static T watch<T extends Object>(BuildContext context) {
    return InheritedModel.inheritFrom<_DepsInherited>(
      context,
      aspect: T,
    )!
        .deps
        .get<T>();
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

    final snapshot = useState<_DepsSnapshot?>(null);

    useEffect(
      () {
        final sub = deps.events.listen((e) {
          snapshot.value = _DepsSnapshot.from(deps);
        });
        return sub.cancel;
      },
      [deps],
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
      snapshot: snapshot.value,
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

class _DepsSnapshot {
  const _DepsSnapshot(this.values);

  factory _DepsSnapshot.from(Deps deps) {
    final values = {
      for (final entry in deps.getAllEntries()) entry.key: deps.peek(entry.key),
    };
    return _DepsSnapshot(values);
  }

  _DepsSnapshot updateWithKey(Deps deps, Type key) => _DepsSnapshot({
        ...values,
        key: deps.peek(key),
      });

  final Map<Object, Object?> values;
}

class _DepsInherited extends InheritedModel<Object> {
  const _DepsInherited({
    required super.child,
    required this.deps,
    required this.snapshot,
  });

  final Deps deps;
  final _DepsSnapshot? snapshot;

  @override
  bool updateShouldNotify(_DepsInherited oldWidget) {
    return deps != oldWidget.deps || snapshot != oldWidget.snapshot;
  }

  @override
  bool updateShouldNotifyDependent(
    _DepsInherited oldWidget,
    Set<Object> dependencies,
  ) {
    if (dependencies.isEmpty) {
      return oldWidget.deps != deps;
    }
    for (final key in dependencies) {
      if (snapshot?.values[key] != oldWidget.snapshot?.values[key]) {
        return true;
      }
    }
    return false;
  }
}
