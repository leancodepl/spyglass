import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:spyglass/spyglass.dart';

typedef Picker<T, R> = R Function(T value);

/// Obtain the nearest [Deps] scope.
Deps useDeps() {
  return DepsProvider.of(useContext());
}

/// Track the specified dependency fully - see [Deps.track]. For the
/// registration-only variant see [useDependencyInstance].
T useDependency<T extends Object>() {
  final deps = useDeps();

  return useStream(deps.track<T>(), initialData: deps.get<T>()).requireData;
}

/// Track the specified dependency's registration only - see
/// [Deps.trackInstance]. For full reactivity see [useDependency].
T useDependencyInstance<T extends Object>() {
  final deps = useDeps();

  return useStream(deps.trackInstance<T>(), initialData: deps.get<T>())
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

/// Shortcuts for obtaining Deps values from BuildContext.
extension DepsContext on BuildContext {
  /// Obtain the nearest [Deps] scope.
  Deps get deps => DepsProvider.of(this);

  /// Read the value of a dependency without listening to changes - the
  /// spyglass equivalent of `context.read<T>()` in `provider`.
  T get<T extends Object>() => deps.get<T>();

  /// Track a dependency fully and rebuild the widget on any change - both
  /// when a new instance is registered under this type, and when the
  /// current instance reports an internal state change (e.g. a wrapped
  /// `ChangeNotifier`/`Listenable` firing its own notifications). This is
  /// the spyglass equivalent of `context.watch<T>()` in `provider`.
  ///
  /// If you only care which instance is registered - not what it's
  /// internally doing - use [trackInstance] instead; it's cheaper, since
  /// it never subscribes to the instance's own notifications at all.
  T track<T extends Object>() => DepsProvider.track<T>(this);

  T? maybeTrack<T extends Object>() => DepsProvider.maybeTrack<T>(this);

  /// Track a dependency's registration only, and rebuild the widget only
  /// when a new instance is registered under this type - NOT when the
  /// current instance reports an internal state change. See [track] for
  /// full reactivity.
  T trackInstance<T extends Object>() => DepsProvider.trackInstance<T>(this);

  T? maybeTrackInstance<T extends Object>() =>
      DepsProvider.maybeTrackInstance<T>(this);

  /// Pick a derived value out of a dependency and rebuild the widget only
  /// when that derived value changes - not on every change to the
  /// dependency itself. The spyglass equivalent of `context.select<T, R>()`
  /// in `provider`.
  R pick<T extends Object, R>(Picker<T, R> picker) =>
      DepsProvider.pick<T, R>(this, picker);

  R? maybePick<T extends Object, R>(Picker<T, R> picker) =>
      DepsProvider.maybePick<T, R>(this, picker);
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
  /// [child]/[builder] by [DepsProvider.of] and [DepsProvider.track].
  final Deps? deps;

  /// A list of dependencies to register on mount and unregister on unmount.
  /// These dependencies will be bound to this widget, effectively.
  final Iterable<Registerable>? register;

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
    return context.getInheritedWidgetOfExactType<_DepsInherited>()?.deps ??
        globalDeps;
  }

  /// Track a dependency fully - see [DepsContext.track].
  static T track<T extends Object>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(
            aspect: (T, const _ObserveOptions(observeState: true)))!
        .deps
        .get<T>();
  }

  static T? maybeTrack<T extends Object>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(
            aspect: (T, const _ObserveOptions(observeState: true)))!
        .deps
        .tryGet<T>();
  }

  /// Track a dependency's registration only - see
  /// [DepsContext.trackInstance].
  static T trackInstance<T extends Object>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(
            aspect: (T, const _ObserveOptions(observeState: false)))!
        .deps
        .get<T>();
  }

  static T? maybeTrackInstance<T extends Object>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(
            aspect: (T, const _ObserveOptions(observeState: false)))!
        .deps
        .tryGet<T>();
  }

  /// Pick a derived value - see [DepsContext.pick].
  static R pick<T extends Object, R>(
      BuildContext context, Picker<T, R> picker) {
    final value = context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(aspect: (
          T,
          _ObserveOptions(observeState: true, picker: picker)
        ))!
        .deps
        .get<T>();
    return picker(value);
  }

  static R? maybePick<T extends Object, R>(
      BuildContext context, Picker<T, R> picker) {
    final value = context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(aspect: (
          T,
          _ObserveOptions(observeState: true, picker: picker)
        ))!
        .deps
        .tryGet<T>();
    return value != null ? picker(value) : null;
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

    final register = this.register;

    // [Dependency] is meant to be a lightweight, cheaply-recreated-every-
    // build config - like a [Widget] - so recreating it here shouldn't tear
    // down the service it describes by default. [Deps.add] already leaves
    // an entry alone when it's registered again under an unchanged
    // [Dependency.cacheKey] (including both being null) - like Element
    // reusing a State when a new Widget arrives with the same type+key -
    // so calling it for every current entry, every build, is enough: keys
    // that didn't actually change are simply left alone by add() itself.
    // We still need to track keys ourselves for the one thing add() can't
    // do - removing a key that disappeared from the list entirely.
    final registeredKeys = useRef<Set<DependencyKey>>(const {});
    final previousDeps = usePrevious(deps);

    useEffect(() {
      if (previousDeps != null && !identical(previousDeps, deps)) {
        // Switched to a different Deps instance entirely - whatever we
        // registered belongs to the old one, not this one.
        registeredKeys.value.forEach(previousDeps.remove);
        registeredKeys.value = const {};
      }

      final currentByKey = <DependencyKey, Dependency<Object>>{
        for (final registerable in register ?? const <Registerable>[])
          for (final dependency in registerable.dependencies)
            dependency.key: dependency,
      };
      final currentKeys = currentByKey.keys.toSet();

      registeredKeys.value.difference(currentKeys).forEach(deps.remove);
      deps.addAll(currentByKey.values);

      registeredKeys.value = currentKeys;
      return null;
    });

    useEffect(
      () => () {
        registeredKeys.value.forEach(deps.remove);
      },
      [deps],
    );

    return _DepsInherited(
      deps: deps,
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

class _DepsInherited extends InheritedWidget {
  const _DepsInherited({
    required super.child,
    required this.deps,
  });

  final Deps deps;

  @override
  bool updateShouldNotify(_DepsInherited oldWidget) {
    return deps != oldWidget.deps;
  }

  @override
  InheritedElement createElement() {
    return _DepsElement(this);
  }
}

class _DepsElement extends InheritedElement {
  _DepsElement(_DepsInherited super.widget);

  @override
  _DepsInherited get widget => super.widget as _DepsInherited;

  /// One real [Deps.track]/[Deps.trackInstance] subscription per (type,
  /// observeState) pair, shared by every dependent watching that
  /// combination - not one per dependent. Keyed on observeState too since
  /// two dependents can ask for the same type with different observeState
  /// values.
  final Map<(Type, bool), StreamSubscription<Object>> _subscriptions = {};

  /// [Deps.track]/[Deps.trackInstance] always emit the current value
  /// immediately on subscribe, even though whoever caused a (type, observeState)
  /// subscription to be created just read that exact value synchronously in
  /// their own build. Tracks which subscriptions haven't delivered that
  /// first, nothing-actually-changed value yet, so [_dispatch] can skip
  /// rebuilding anyone for it - otherwise every dependency observed at all
  /// leaves behind one spurious rebuild that gets silently cashed in on
  /// whatever the next unrelated pump happens to be.
  final Set<(Type, bool)> _pendingFirstEmission = {};

  /// Which dependents are watching a given type, and their per-dependent
  /// picker state - so dispatching a value only touches watchers of that
  /// type instead of every dependent of this element.
  final Map<Type, Map<Element, _Watcher>> _watchersByType = {};

  @override
  void updated(_DepsInherited oldWidget) {
    if (widget.deps != oldWidget.deps) {
      for (final sub in _subscriptions.values) {
        sub.cancel();
      }
      _subscriptions.clear();
      _pendingFirstEmission.clear();
      _watchersByType.clear();
    }
    super.updated(oldWidget);
  }

  @override
  void updateDependencies(Element dependent, Object? aspect) {
    setDependencies(dependent, aspect);
  }

  @override
  void setDependencies(Element dependent, Object? value) {
    if (value == null) {
      return;
    }
    if (value is! (Type, _ObserveOptions)) {
      throw ArgumentError.value(
          value, 'value', 'value must be a (Type, _ObserveOptions)');
    }
    final (type, options) = value;

    final watchers = _watchersByType.putIfAbsent(type, () => {});
    if (watchers.containsKey(dependent)) {
      // Already set up - matches the old map's `??=`, which likewise only
      // ever honored the first (dependent, type) registration.
      return;
    }
    watchers[dependent] = _Watcher(
      observeState: options.observeState,
      picker: options.picker,
    );

    final subscriptionKey = (type, options.observeState);
    _subscriptions.putIfAbsent(subscriptionKey, () {
      _pendingFirstEmission.add(subscriptionKey);
      final stream = options.observeState
          ? widget.deps.track(key: type)
          : widget.deps.trackInstance(key: type);
      return stream.listen((value) => _dispatch(subscriptionKey, value));
    });
  }

  void _dispatch((Type, bool) subscriptionKey, Object value) {
    // Picker watchers already skip their own first-observed value via
    // hasPicked below (whatever that happens to be, first-ever or not),
    // so this only needs to protect non-picker watchers, which have no
    // baseline tracking of their own.
    final isFirstEmission = _pendingFirstEmission.remove(subscriptionKey);

    final (type, observeState) = subscriptionKey;
    final watchers = _watchersByType[type];
    if (watchers == null) {
      return;
    }
    for (final MapEntry(key: dependent, value: watcher) in watchers.entries) {
      if (watcher.observeState != observeState) {
        continue;
      }
      if (watcher.picker case final picker?) {
        // reason: picker is stored as a bare Function to keep _Watcher
        // non-generic, mirroring the dynamic cast the old per-dependent
        // pipeline already did.
        final picked = (picker as dynamic)(value);
        if (!watcher.hasPicked) {
          // First value after (re)subscribing just sets the baseline - like
          // pairwise() not emitting until its second item.
          watcher
            ..hasPicked = true
            ..lastPicked = picked;
          continue;
        }
        if (picked == watcher.lastPicked) {
          continue;
        }
        watcher.lastPicked = picked;
      } else if (isFirstEmission) {
        continue;
      }
      dependent.markNeedsBuild();
    }
  }

  @override
  void removeDependent(Element dependent) {
    for (final type in [..._watchersByType.keys]) {
      final watchers = _watchersByType[type];
      if (watchers == null || watchers.remove(dependent) == null) {
        continue;
      }
      _pruneSubscriptionsIfUnused(type, watchers);
    }
    super.removeDependent(dependent);
  }

  void _pruneSubscriptionsIfUnused(Type type, Map<Element, _Watcher> watchers) {
    if (watchers.isEmpty) {
      _watchersByType.remove(type);
      _subscriptions.remove((type, true))?.cancel();
      _subscriptions.remove((type, false))?.cancel();
      _pendingFirstEmission
        ..remove((type, true))
        ..remove((type, false));
      return;
    }
    if (!watchers.values.any((w) => w.observeState)) {
      _subscriptions.remove((type, true))?.cancel();
      _pendingFirstEmission.remove((type, true));
    }
    if (!watchers.values.any((w) => !w.observeState)) {
      _subscriptions.remove((type, false))?.cancel();
      _pendingFirstEmission.remove((type, false));
    }
  }

  @override
  void unmount() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _pendingFirstEmission.clear();
    _watchersByType.clear();
    super.unmount();
  }
}

class _Watcher {
  _Watcher({required this.observeState, this.picker});

  final bool observeState;
  final Function? picker;
  bool hasPicked = false;
  Object? lastPicked;
}

class ListenableDependency<T extends Listenable> extends Dependency<T> {
  const ListenableDependency(
    super.create, {
    super.debugLabel,
    super.dispose,
    super.observe,
    super.tags,
    super.update,
  });

  @override
  DependencyObserver<T> createObserver(T value) =>
      ListenableDependencyObserver(value);
}

class ListenableDependencyObserver<T extends Listenable>
    extends DependencyObserver<T> {
  ListenableDependencyObserver(this.listenable) {
    listenable.addListener(_listener);
  }
  final T listenable;

  void _listener() => notifyStateChanged();

  @override
  Future<void> dispose() async {
    listenable.removeListener(_listener);
  }
}

class ChangeNotifierDependency<T extends ChangeNotifier>
    extends ListenableDependency<T> {
  const ChangeNotifierDependency(
    super.create, {
    super.debugLabel,
    super.observe,
    super.tags,
    super.update,
    FutureOr<void> Function(T value)? dispose,
  }) : super(dispose: dispose ?? _dispose);

  static void _dispose(ChangeNotifier value) {
    value.dispose();
  }
}

@immutable
class _ObserveOptions {
  const _ObserveOptions({required this.observeState, this.picker});

  final bool observeState;
  final Function? picker;
}
