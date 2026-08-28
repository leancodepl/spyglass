import 'types.dart';

/// Thrown by `Deps.get` and `Deps.tryGet` when no dependency is registered
/// under [key] in this `Deps` scope or any of its ancestors.
class DependencyNotRegisteredException implements Exception {
  const DependencyNotRegisteredException(this.key);

  /// The key that was looked up.
  final DependencyKey key;

  @override
  String toString() =>
      'DependencyNotRegisteredException: No dependency is registered for '
      '$key in this Deps scope or any of its ancestors.\n'
      'Check that it was added via Deps.add/Deps.replace, or listed in the '
      'register: of a DepsProvider above this point in the widget tree - '
      'and that the type matches exactly, since Deps looks up by exact '
      'runtime Type.';
}

/// Thrown by `Deps.get` when [key] is registered but its value hasn't
/// finished resolving yet - e.g. `Dependency.create` is asynchronous and
/// still running.
class DependencyNotResolvedException implements Exception {
  const DependencyNotResolvedException(this.key);

  /// The key that was looked up.
  final DependencyKey key;

  @override
  String toString() =>
      'DependencyNotResolvedException: $key is registered, but its value '
      "hasn't resolved yet - Dependency.create is still running (likely "
      'asynchronous).\n'
      'Use Deps.tryGet for a nullable result instead of throwing, or await '
      'Deps.ensureResolved([$key]) before calling Deps.get.';
}

/// Thrown when an operation needs this `Deps` scope to still be alive, but
/// `Deps.dispose` has already been called on it - by `Deps.add` (adding to a
/// disposed scope makes no sense) and by `Deps.get`/`Deps.tryGet` (resolving
/// a value from a scope whose dependencies have all been torn down doesn't
/// either).
class DepsDisposedException implements Exception {
  const DepsDisposedException({this.key});

  /// The dependency key involved, if the failing operation was about a
  /// specific key (e.g. `Deps.get`) rather than the scope as a whole (e.g.
  /// `Deps.add`).
  final DependencyKey? key;

  @override
  String toString() {
    final about = key == null ? '' : ' (while resolving $key)';
    return 'DepsDisposedException: This Deps scope has already been '
        'disposed$about and can no longer register or resolve '
        'dependencies.\n'
        "If this came from a widget, you're likely holding onto a Deps "
        'reference that outlived its DepsProvider - e.g. a callback that '
        'captured a Deps and ran after the provider that owned it unmounted.';
  }
}

/// Thrown when resolving [key] re-enters its own `Dependency.create` before
/// the first call has finished - i.e. a dependency, directly or indirectly,
/// depends on itself.
class DependencyCycleException implements Exception {
  const DependencyCycleException(this.key);

  /// The key whose creation cycled back on itself.
  final DependencyKey key;

  @override
  String toString() =>
      'DependencyCycleException: Creating $key triggered another attempt to '
      'resolve $key before the first one finished.\n'
      'This usually means Dependency.create for $key - directly, or '
      'indirectly via Deps.get inside it - depends on itself.';
}
