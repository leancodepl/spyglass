import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:spyglass/spyglass.dart';

import 'deps_context.dart';
import 'deps_diagnostics.dart';

/// Register on mount;  Unregister on unmount.
class DepsProvider extends StatefulWidget {
  /// Introduces a scope and/or registers [register] - see the fields below.
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
  /// [child]/[builder] by [DepsProvider.of] and [DepsProvider.watch].
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

  /// Watch a dependency fully - see [DepsContext.watch].
  static T watch<T extends Object>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(
            aspect: (T, const _ObserveOptions(observeState: true)))!
        .deps
        .get<T>();
  }

  /// Like [watch], but returns `null` instead of throwing when [T] isn't
  /// registered.
  static T? maybeWatch<T extends Object>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(
            aspect: (T, const _ObserveOptions(observeState: true)))!
        .deps
        .tryGet<T>();
  }

  /// Watch a dependency's registration only - see
  /// [DepsContext.watchInstance].
  static T watchInstance<T extends Object>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(
            aspect: (T, const _ObserveOptions(observeState: false)))!
        .deps
        .get<T>();
  }

  /// Like [watchInstance], but returns `null` instead of throwing when [T]
  /// isn't registered.
  static T? maybeWatchInstance<T extends Object>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(
            aspect: (T, const _ObserveOptions(observeState: false)))!
        .deps
        .tryGet<T>();
  }

  /// Select a derived value - see [DepsContext.select].
  static R select<T extends Object, R>(
      BuildContext context, Selector<T, R> selector) {
    final value = context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(aspect: (
          T,
          _ObserveOptions(observeState: true, selector: selector)
        ))!
        .deps
        .get<T>();
    return selector(value);
  }

  /// Like [select], but returns `null` instead of throwing when [T] isn't
  /// registered.
  static R? maybeSelect<T extends Object, R>(
      BuildContext context, Selector<T, R> selector) {
    final value = context
        .dependOnInheritedWidgetOfExactType<_DepsInherited>(aspect: (
          T,
          _ObserveOptions(observeState: true, selector: selector)
        ))!
        .deps
        .tryGet<T>();
    return value != null ? selector(value) : null;
  }

  @override
  State<DepsProvider> createState() => _DepsProviderState();
}

class _DepsProviderState extends State<DepsProvider> {
  // The scope currently provided to descendants - either `widget.deps`, a
  // fresh fork of the parent scope, or the parent scope itself, depending on
  // `widget.deps`/`widget.introduceScope`.
  Deps? _deps;

  // Non-null exactly when this widget forked its own scope (rather than
  // being handed one via `widget.deps`, or passing the parent scope
  // through) and therefore owns its lifecycle.
  Deps? _ownedDeps;

  Deps? _lastDepsProp;
  Deps? _lastParentScope;
  bool _lastIntroduceScope = false;

  Set<DependencyKey> _registeredKeys = const {};
  late Deps _registeredIn;

  void _updateDeps(Deps parentScope) {
    final depsProp = widget.deps;
    final introduceScope = widget.introduceScope;

    final unchanged = _deps != null &&
        identical(_lastDepsProp, depsProp) &&
        identical(_lastParentScope, parentScope) &&
        _lastIntroduceScope == introduceScope;
    if (unchanged) {
      return;
    }

    final previouslyOwned = _ownedDeps;

    _deps = depsProp ?? (introduceScope ? parentScope.fork() : parentScope);
    _ownedDeps = (introduceScope && depsProp == null) ? _deps : null;

    _lastDepsProp = depsProp;
    _lastParentScope = parentScope;
    _lastIntroduceScope = introduceScope;

    if (previouslyOwned != null && !identical(previouslyOwned, _ownedDeps)) {
      previouslyOwned.dispose();
    }
  }

  void _updateRegistrations() {
    final deps = _deps!;

    if (_registeredKeys.isNotEmpty && !identical(_registeredIn, deps)) {
      // Switched to a different Deps instance entirely - whatever we
      // registered belongs to the old one, not this one.
      _registeredKeys.forEach(_registeredIn.remove);
      _registeredKeys = const {};
    }

    // [Dependency] is meant to be a lightweight, cheaply-recreated-every-
    // build config - like a [Widget] - so recreating it here shouldn't tear
    // down the service it describes by default. [Deps.add] already leaves
    // an entry alone when it's registered again under an unchanged
    // [Dependency.cacheKey] (including both being null) - like Element
    // reusing a State when a new Widget arrives with the same type+key -
    // so calling it for every current entry, every build, is enough: keys
    // that didn't actually change are simply left alone by add() itself.
    // We still need to watch keys ourselves for the one thing add() can't
    // do - removing a key that disappeared from the list entirely.
    final currentByKey = <DependencyKey, Dependency<Object>>{
      for (final registerable in widget.register ?? const <Registerable>[])
        for (final dependency in registerable.dependencies)
          dependency.key: dependency,
    };
    final currentKeys = currentByKey.keys.toSet();

    _registeredKeys.difference(currentKeys).forEach(deps.remove);
    deps.addAll(currentByKey.values);

    _registeredKeys = currentKeys;
    _registeredIn = deps;
  }

  @override
  void dispose() {
    _registeredKeys.forEach(_registeredIn.remove);
    _ownedDeps?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parentScope = DepsProvider.of(context);
    _updateDeps(parentScope);
    _updateRegistrations();

    return _DepsInherited(
      deps: _deps!,
      child: Builder(
        builder: (context) {
          var result = widget.child;
          if (widget.builder case final builder?) {
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

  /// Surfaces [deps] - its own registered dependencies, and (with
  /// [spyglassDiagnosticsMode] enabled) every descendant scope - in the
  /// widget inspector/`debugDumpApp()`. This is on the internal
  /// `_DepsInherited` node one level below [DepsProvider], not
  /// [DepsProvider] itself - the live scope (possibly a fresh [Deps.fork])
  /// is only known once `build()` runs, and that's where it lives. In
  /// DevTools, turn off "Show only widgets created by user" to see it.
  @override
  List<DiagnosticsNode> debugDescribeChildren() => [
        deps.toDiagnosticsNode(name: 'deps'),
      ];
}

class _DepsElement extends InheritedElement {
  _DepsElement(_DepsInherited super.widget);

  @override
  _DepsInherited get widget => super.widget as _DepsInherited;

  /// One real [Deps.watch]/[Deps.watchInstance] subscription per (type,
  /// observeState) pair, shared by every dependent watching that
  /// combination - not one per dependent. Keyed on observeState too since
  /// two dependents can ask for the same type with different observeState
  /// values.
  final Map<(Type, bool), StreamSubscription<Object>> _subscriptions = {};

  /// [Deps.watch]/[Deps.watchInstance] always emit the current value
  /// immediately on subscribe, even though whoever caused a (type, observeState)
  /// subscription to be created just read that exact value synchronously in
  /// their own build. Tracks which subscriptions haven't delivered that
  /// first, nothing-actually-changed value yet, so [_dispatch] can skip
  /// rebuilding anyone for it - otherwise every dependency observed at all
  /// leaves behind one spurious rebuild that gets silently cashed in on
  /// whatever the next unrelated pump happens to be.
  final Set<(Type, bool)> _pendingFirstEmission = {};

  /// Which dependents are watching a given type, and their per-dependent
  /// selector state - so dispatching a value only touches watchers of that
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
      selector: options.selector,
    );

    final subscriptionKey = (type, options.observeState);
    _subscriptions.putIfAbsent(subscriptionKey, () {
      _pendingFirstEmission.add(subscriptionKey);
      final stream = options.observeState
          ? widget.deps.watch(key: type)
          : widget.deps.watchInstance(key: type);
      return stream.listen((value) => _dispatch(subscriptionKey, value));
    });
  }

  void _dispatch((Type, bool) subscriptionKey, Object value) {
    // Selector watchers already skip their own first-observed value via
    // hasSelected below (whatever that happens to be, first-ever or not),
    // so this only needs to protect non-selector watchers, which have no
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
      if (watcher.selector case final selector?) {
        // reason: selector is stored as a bare Function to keep _Watcher
        // non-generic, mirroring the dynamic cast the old per-dependent
        // pipeline already did.
        final selected = (selector as dynamic)(value);
        if (!watcher.hasSelected) {
          // First value after (re)subscribing just sets the baseline - like
          // pairwise() not emitting until its second item.
          watcher
            ..hasSelected = true
            ..lastSelected = selected;
          continue;
        }
        if (selected == watcher.lastSelected) {
          continue;
        }
        watcher.lastSelected = selected;
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
  _Watcher({required this.observeState, this.selector});

  final bool observeState;
  final Function? selector;
  bool hasSelected = false;
  Object? lastSelected;
}

@immutable
class _ObserveOptions {
  const _ObserveOptions({required this.observeState, this.selector});

  final bool observeState;
  final Function? selector;
}
