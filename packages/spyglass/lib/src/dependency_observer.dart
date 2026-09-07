import 'package:meta/meta.dart';

/// A factory function to create a [DependencyObserver] for a dependency.
typedef DependencyObserverFactory<T extends Object> = DependencyObserver<T>?
    Function(T value);

/// Observes internal state changes of an already-resolved dependency value -
/// e.g. a wrapped `ChangeNotifier`/`Listenable` firing its own notifications
/// - as opposed to the value itself being replaced. See
/// `Dependency.createObserver`.
///
/// The framework creates and disposes exactly one observer per resolved
/// value, not one per subscriber to `Deps.watch`; call [notifyStateChanged]
/// whenever the observed value's state changes and every current
/// `Deps.watch` subscriber for this key is notified.
abstract class DependencyObserver<T extends Object> {
  void Function()? _onChanged;

  /// Wires this observer up to its owning `ManagedDependency`. Called by the
  /// framework right after construction - implementers should not call this.
  @internal
  void attach(void Function() onChanged) {
    _onChanged = onChanged;
  }

  /// Call this whenever the observed value's internal state changes, to
  /// notify anyone tracking this dependency via `Deps.watch` - without
  /// needing to know about `Deps` or `ManagedDependency` directly.
  @protected
  void notifyStateChanged() {
    _onChanged?.call();
  }

  /// Called once, when the observed value itself is replaced or removed -
  /// release whatever [attach] wired up (e.g. remove a listener).
  Future<void> dispose();
}
