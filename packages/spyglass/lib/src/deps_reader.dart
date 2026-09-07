import 'types.dart';

/// Passed to `Dependency.create` instead of a plain `Deps` - reads made
/// through it are how a dependency declares what it reacts to, instead of a
/// separate, easy-to-forget list.
///
/// [get] is a plain, untracked read - same as `Deps.get`, and has no effect
/// on when `Dependency.create` is re-invoked. [watchInstance] is a *tracked*
/// read: it returns the dependency's current value, exactly like [get], but
/// also registers it so that `Dependency.create` is re-invoked whenever a
/// new instance is registered under that key (`Deps.watchInstance`
/// semantics - not the dependency's own internal state changes; see
/// `Deps.watch` for why that's deliberately out of scope here).
///
/// The tracked set is rediscovered on every call to `Dependency.create` -
/// whichever keys it reads via [watchInstance] *this time* are what it's
/// subscribed to next, so branching on `Dependency.create`'s `oldValue` to
/// read different keys on different runs works correctly, with
/// subscriptions adjusting to match.
abstract class DepsReader {
  /// An untracked read - equivalent to `Deps.get`. Reading a key this way
  /// doesn't cause `Dependency.create` to be re-invoked when it changes.
  T get<T extends Object>([DependencyKey? key]);

  /// A tracked read - equivalent to `Deps.watchInstance`, except it returns
  /// the current value directly instead of a `Stream`. Reading a key this
  /// way means `Dependency.create` is re-invoked whenever a new instance is
  /// registered under it.
  T watchInstance<T extends Object>([DependencyKey? key]);
}
