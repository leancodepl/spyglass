import 'package:flutter/widgets.dart';
import 'package:spyglass/spyglass.dart';

import 'deps_provider.dart';

/// Derives an [R] from a resolved [T] value - see [DepsContext.select].
typedef Selector<T, R> = R Function(T value);

/// Shortcuts for obtaining Deps values from BuildContext.
extension DepsContext on BuildContext {
  /// Obtain the nearest [Deps] scope.
  Deps get deps => DepsProvider.of(this);

  /// Read the value of a dependency without listening to changes - the
  /// spyglass equivalent of `context.read<T>()` in `provider`.
  T get<T extends Object>() => deps.get<T>();

  /// Watch a dependency fully and rebuild the widget on any change - both
  /// when a new instance is registered under this type, and when the
  /// current instance reports an internal state change (e.g. a wrapped
  /// `ChangeNotifier`/`Listenable` firing its own notifications). This is
  /// the spyglass equivalent of `context.watch<T>()` in `provider`.
  ///
  /// If you only care which instance is registered - not what it's
  /// internally doing - use [watchInstance] instead; it's cheaper, since
  /// it never subscribes to the instance's own notifications at all.
  T watch<T extends Object>() => DepsProvider.watch<T>(this);

  /// Like [watch], but returns `null` instead of throwing when [T] isn't
  /// registered.
  T? maybeWatch<T extends Object>() => DepsProvider.maybeWatch<T>(this);

  /// Watch a dependency's registration only, and rebuild the widget only
  /// when a new instance is registered under this type - NOT when the
  /// current instance reports an internal state change. See [watch] for
  /// full reactivity.
  T watchInstance<T extends Object>() => DepsProvider.watchInstance<T>(this);

  /// Like [watchInstance], but returns `null` instead of throwing when [T]
  /// isn't registered.
  T? maybeWatchInstance<T extends Object>() =>
      DepsProvider.maybeWatchInstance<T>(this);

  /// Select a derived value out of a dependency and rebuild the widget only
  /// when that derived value changes - not on every change to the
  /// dependency itself. The spyglass equivalent of `context.select<T, R>()`
  /// in `provider`.
  R select<T extends Object, R>(Selector<T, R> selector) =>
      DepsProvider.select<T, R>(this, selector);

  /// Like [select], but returns `null` instead of throwing when [T] isn't
  /// registered.
  R? maybeSelect<T extends Object, R>(Selector<T, R> selector) =>
      DepsProvider.maybeSelect<T, R>(this, selector);
}
