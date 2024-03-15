import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:spyglass/src/deps.dart';

T? useDependency<T extends Object>([Object? key]) {
  final context = useContext();
  final deps = DepsProvider.of(context);
  return useStream(deps.watch<T>(key)).data;
}

extension DepsContext on BuildContext {
  Deps get deps => DepsProvider.of(this);

  T get<T extends Object>([Object? key]) => deps.get<T>(key);
  T watch<T extends Object>([Object? key]) =>
      DepsProvider.watch<T>(this, key: key);
}

class DepsProvider extends HookWidget {
  const DepsProvider({
    super.key,
    this.deps,
    required this.child,
  });

  final Deps? deps;
  final Widget child;

  static final _depsAspect = Object();

  static Deps of(BuildContext context) {
    return InheritedModel.inheritFrom<_DepsInherited>(
          context,
          aspect: _depsAspect,
        )?.scope ??
        globalDeps;
  }

  static T watch<T extends Object>(BuildContext context, {Object? key}) {
    final effectiveKey = DependencyKey<T>(key);
    return InheritedModel.inheritFrom<_DepsInherited>(
      context,
      aspect: effectiveKey,
    )!
        .scope
        .get<T>(key);
  }

  @override
  Widget build(BuildContext context) {
    final parentScope = of(context);
    final deps = useMemoized(
      () => this.deps ?? parentScope.fork(),
      [
        this.deps,
        parentScope,
      ],
    );
    final snapshot = useState<_DepsSnapshot?>(null);

    useEffect(() {
      final sub = deps.events.listen((e) {
        snapshot.value = _DepsSnapshot.of(deps);
      });
      return sub.cancel;
    }, [deps]);

    return _DepsInherited(scope: deps, snapshot: snapshot.value, child: child);
  }
}

class _DepsSnapshot {
  const _DepsSnapshot(this.values);

  factory _DepsSnapshot.of(Deps deps) {
    final values = {
      for (final entry in deps.flattened().entries) entry.key: entry,
    };
    return _DepsSnapshot(values);
  }

  final Map<Object, Dependency<Object>> values;
}

class _DepsInherited extends InheritedModel<Object> {
  const _DepsInherited({
    required super.child,
    required this.scope,
    required this.snapshot,
  });

  final Deps scope;
  final _DepsSnapshot? snapshot;

  @override
  bool updateShouldNotify(_DepsInherited oldWidget) {
    return scope != oldWidget.scope || snapshot != oldWidget.snapshot;
  }

  @override
  bool updateShouldNotifyDependent(
    _DepsInherited oldWidget,
    Set<Object> dependencies,
  ) {
    if (dependencies.length == 1 &&
        dependencies.single == DepsProvider._depsAspect) {
      return oldWidget.scope != scope;
    }
    for (final key in dependencies) {
      if (key == DepsProvider._depsAspect) {
        continue;
      }
      if (snapshot?.values[key] != oldWidget.snapshot?.values[key]) {
        return true;
      }
    }
    return false;
  }
}
