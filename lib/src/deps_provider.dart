import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:spyglass/src/deps.dart';

class DepsProvider extends HookWidget {
  const DepsProvider({
    super.key,
    this.deps,
    required this.child,
  });

  final Deps? deps;
  final Widget child;

  static Deps of(BuildContext context) {
    return InheritedModel.inheritFrom<_DepsInherited>(context)?.scope ??
        globalDeps;
  }

  static T watch<T>(BuildContext context, {Object? key}) {
    final effectiveKey = key ?? T;
    return InheritedModel.inheritFrom<_DepsInherited>(
      context,
      aspect: effectiveKey,
    )?.scope.get(effectiveKey) as T;
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
    return snapshot != oldWidget.snapshot;
  }

  @override
  bool updateShouldNotifyDependent(
    _DepsInherited oldWidget,
    Set<Object> dependencies,
  ) {
    if (oldWidget.scope != scope) {
      return true;
    }
    for (final key in dependencies) {
      if (snapshot?.values[key] != oldWidget.snapshot?.values[key]) {
        return true;
      }
    }
    return false;
  }
}
