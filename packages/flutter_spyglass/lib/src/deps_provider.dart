import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:spyglass/spyglass.dart';

Deps useDeps() {
  return DepsProvider.of(useContext());
}

T useDependency<T extends Object>() {
  final context = useContext();
  final deps = DepsProvider.of(context);
  return useStream(deps.watch<T>(), initialData: deps.get<T>()).requireData;
}

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
    this.child,
    this.builder,
  }) : assert(child != null || builder != null);

  final Deps? deps;
  final Iterable<Dependency<Object>>? register;
  final bool introduceScope;
  final Widget? child;
  final TransitionBuilder? builder;

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

    final registerCalled = useRef(false);
    final register = this.register;

    useEffect(
      () {
        if (registerCalled.value || register == null) {
          return null;
        }

        registerCalled.value = true;

        final unregister = deps.addMany(register);

        return unregister;
      },
      [deps, register?.map((e) => e.key).toList()],
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
