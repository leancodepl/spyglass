import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:spyglass/spyglass.dart';

T? useDependency<T extends Object>() {
  final context = useContext();
  final deps = DepsProvider.of(context);
  return useStream(deps.watch<T>()).data;
}

void useRegisterDependency<T extends Object>({
  required Constructor<T> create,
  Disposer<T>? dispose,
  String? debugLabel,
}) {
  final context = useContext();
  final deps = DepsProvider.of(context);
  useEffect(() {
    final dependency = Dependency<T>(
      create: create,
      dispose: dispose,
      debugLabel: debugLabel,
    );
    deps.add(dependency);
    return () => deps.remove(dependency.key);
  });
}

extension DepsContext on BuildContext {
  Deps get deps => DepsProvider.of(this);

  T get<T extends Object>() => deps.get<T>();
  T watch<T extends Object>() => DepsProvider.watch<T>(this);
}

/// Register on mount;  Unregister on unmount.
class DepsProvider extends HookWidget {
  const DepsProvider({
    super.key,
    this.deps,
    this.register,
    this.introduceScope = true,
    required this.child,
  });

  final Deps? deps;
  final Iterable<Dependency<Object>>? register;
  final bool introduceScope;
  final Widget child;

  static Deps of(BuildContext context) {
    return InheritedModel.inheritFrom<_DepsInherited>(
          context,
        )?.deps ??
        globalDeps;
  }

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
    useEffect(() {
      if (introduceScope && this.deps == null) {
        return () {
          deps.dispose();
        };
      }
      return null;
    }, [deps, introduceScope, this.deps]);

    final snapshot = useState<_DepsSnapshot?>(null);

    useEffect(() {
      final sub = deps.events.listen((e) {
        snapshot.value = _DepsSnapshot.of(deps);
      });
      return sub.cancel;
    }, [deps]);

    final registerCalled = useRef(false);
    final register = this.register;

    useEffect(() {
      if (registerCalled.value || register == null) {
        return null;
      }

      registerCalled.value = true;

      for (final dep in register) {
        deps.add(dep);
      }

      final keys = register.map((dep) => dep.key).toList();

      return () {
        for (final key in keys) {
          deps.remove(key);
        }
      };
    }, [deps, register]);

    return _DepsInherited(
      deps: deps,
      snapshot: snapshot.value,
      child: child,
    );
  }
}

class _DepsSnapshot {
  const _DepsSnapshot(this.values);

  factory _DepsSnapshot.of(Deps deps) {
    final values = {
      for (final scope in deps.scopeChain.toList().reversed)
        for (final entry in scope.entries) entry.key: scope.peek(entry.key),
    };
    return _DepsSnapshot(values);
  }

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
