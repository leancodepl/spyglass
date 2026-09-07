import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:spyglass/spyglass.dart';

import 'deps_provider.dart';

/// Obtain the nearest [Deps] scope.
Deps useDeps() {
  return DepsProvider.of(useContext());
}

/// Watch the specified dependency fully - see [Deps.watch]. For the
/// registration-only variant see [useDependencyInstance].
T useDependency<T extends Object>() {
  final deps = useDeps();

  return useStream(deps.watch<T>(), initialData: deps.get<T>()).requireData;
}

/// Watch the specified dependency's registration only - see
/// [Deps.watchInstance]. For full reactivity see [useDependency].
T useDependencyInstance<T extends Object>() {
  final deps = useDeps();

  return useStream(deps.watchInstance<T>(), initialData: deps.get<T>())
      .requireData;
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
      final unregister = deps.addAll(dependencies);
      return unregister;
    },
    keys ?? dependencies.map((e) => e.key).toList(),
  );
}
