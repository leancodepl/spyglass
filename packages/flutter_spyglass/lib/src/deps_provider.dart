import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:spyglass/spyglass.dart';

import 'deps_context.dart';
import 'deps_diagnostics.dart';

/// A [Deps] fork shared by every [DepsProvider] currently referencing the
/// same [DepsProvider.sharedKey] under the same nearest ancestor scope -
/// created when the first of them acquires it, disposed once the last one
/// releases it. See [_SharedDepsRegistry].
class _SharedDepsEntry {
  _SharedDepsEntry(this.deps);

  final Deps deps;

  /// How many [DepsProvider]s currently hold this entry (i.e. have acquired
  /// it and not yet released it).
  int refCount = 1;

  /// How many of those holders currently list a given key in [DepsProvider.
  /// register] - so one holder unmounting doesn't remove (and dispose) a
  /// dependency another holder sharing this scope still relies on.
  final Map<DependencyKey, int> registrationRefCounts = {};
}

/// Ref-counted cache of [_SharedDepsEntry]s, keyed by [DepsProvider.
/// sharedKey]. One lives per ancestor [DepsProvider] (handed down via
/// [_DepsInherited]) for its own descendants to share; [_fallbackRegistries]
/// covers the case where a [DepsProvider.sharedKey] is used with no ancestor
/// [DepsProvider] at all.
class _SharedDepsRegistry {
  final Map<Object, _SharedDepsEntry> _entries = {};

  _SharedDepsEntry acquire(Object key, Deps parentScope) {
    final existing = _entries[key];
    if (existing != null) {
      existing.refCount++;
      return existing;
    }
    final entry = _SharedDepsEntry(parentScope.fork());
    _entries[key] = entry;
    return entry;
  }

  void release(Object key) {
    final entry = _entries[key];
    if (entry == null) {
      return;
    }
    if (--entry.refCount <= 0) {
      _entries.remove(key);
      entry.deps.dispose();
    }
  }
}

/// Registries for use when a [DepsProvider.sharedKey] is acquired with no
/// ancestor [DepsProvider] to hold one - keyed on the parent [Deps] scope
/// (typically [globalDeps]) itself, via [Expando], so this doesn't need any
/// cleanup of its own: an entry disappears along with the [Deps] it's keyed
/// on. Expected to be rare - most shared scopes have a common ancestor
/// [DepsProvider] to hang off of.
final _fallbackRegistries =
    Expando<_SharedDepsRegistry>('sharedDepsRegistries');

/// Register on mount;  Unregister on unmount.
class DepsProvider extends StatefulWidget {
  /// Introduces a scope and/or registers [register] - see the fields below.
  const DepsProvider({
    super.key,
    this.deps,
    this.sharedKey,
    this.register,
    this.introduceScope = true,
    this.child,
    this.builder,
  })  : assert(child != null || builder != null),
        assert(deps == null || sharedKey == null,
            'Pass either deps or sharedKey, not both.'),
        assert(sharedKey == null || introduceScope,
            'sharedKey has no effect when introduceScope is false.');

  /// Provide a custom [Deps] instance that dependencies listed in [register]
  /// should be added to. This will also influence the provided scope to the
  /// [child]/[builder] by [DepsProvider.of] and [DepsProvider.watch].
  final Deps? deps;

  /// When set, every [DepsProvider] sharing this same key under the same
  /// nearest ancestor scope resolves to one underlying forked [Deps] -
  /// created when the first of them mounts, disposed once the last of them
  /// unmounts. Useful for a multi-screen flow that should share one scope
  /// without a single common ancestor widget spanning exactly its lifetime.
  ///
  /// [Dependency] keys registered via [register] are similarly shared: a key
  /// registered by more than one of these [DepsProvider]s is only actually
  /// removed - and disposed - once none of them still register it. This
  /// assumes a given key means the same thing (the same [Dependency.
  /// cacheKey], where used) across all of them.
  final Object? sharedKey;

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
  // shared scope acquired via `widget.sharedKey`, a fresh fork of the parent
  // scope, or the parent scope itself, depending on `widget.deps`/
  // `widget.sharedKey`/`widget.introduceScope`.
  Deps? _deps;

  // Non-null exactly when this widget forked its own private (non-shared)
  // scope and therefore owns its lifecycle outright.
  Deps? _ownedDeps;

  // Non-null exactly when `_deps` was acquired from a shared entry (via
  // `widget.sharedKey`), which this widget must eventually release rather
  // than dispose directly - other DepsProviders may still be using it.
  _SharedDepsEntry? _sharedEntry;
  _SharedDepsRegistry? _registry;
  Object? _sharedKeyHeld;

  // This widget's own registry, offered to its descendants (via
  // `_DepsInherited`) for their own `sharedKey` usage - independent of
  // whether this widget uses `sharedKey` itself.
  final _SharedDepsRegistry _ownRegistry = _SharedDepsRegistry();

  Deps? _lastDepsProp;
  Deps? _lastParentScope;
  Object? _lastSharedKey;
  bool _lastIntroduceScope = false;

  Set<DependencyKey> _registeredKeys = const {};
  late Deps _registeredIn;

  // The shared entry `_registeredIn`'s keys' ref counts live in, if any -
  // tracked separately from `_sharedEntry` since the latter can already
  // point at a *new* target by the time registrations catch up to it.
  _SharedDepsEntry? _registeredInEntry;

  void _updateDeps(Deps parentScope, _DepsInherited? inherited) {
    final depsProp = widget.deps;
    final sharedKey = widget.sharedKey;
    final introduceScope = widget.introduceScope;

    final unchanged = _deps != null &&
        identical(_lastDepsProp, depsProp) &&
        identical(_lastParentScope, parentScope) &&
        _lastSharedKey == sharedKey &&
        _lastIntroduceScope == introduceScope;
    if (unchanged) {
      return;
    }

    final previouslyOwnedDeps = _ownedDeps;
    final previousRegistry = _registry;
    final previousSharedKey = _sharedKeyHeld;

    _ownedDeps = null;
    _registry = null;
    _sharedEntry = null;
    _sharedKeyHeld = null;

    if (depsProp != null) {
      _deps = depsProp;
    } else if (sharedKey != null) {
      final registry = inherited?.registry ??
          (_fallbackRegistries[parentScope] ??= _SharedDepsRegistry());
      final entry = registry.acquire(sharedKey, parentScope);
      _deps = entry.deps;
      _sharedEntry = entry;
      _registry = registry;
      _sharedKeyHeld = sharedKey;
    } else if (introduceScope) {
      _deps = parentScope.fork();
      _ownedDeps = _deps;
    } else {
      _deps = parentScope;
    }

    _lastDepsProp = depsProp;
    _lastParentScope = parentScope;
    _lastSharedKey = sharedKey;
    _lastIntroduceScope = introduceScope;

    // Acquire the replacement before releasing whatever we held before -
    // if they happen to resolve to the same shared entry, this avoids
    // transiently dropping its ref count to zero.
    if (previouslyOwnedDeps != null &&
        !identical(previouslyOwnedDeps, _ownedDeps)) {
      previouslyOwnedDeps.dispose();
    }
    if (previousRegistry != null && !identical(previousRegistry, _registry)) {
      previousRegistry.release(previousSharedKey!);
    }
  }

  void _updateRegistrations() {
    final deps = _deps!;
    final entry = _sharedEntry;

    if (_registeredKeys.isNotEmpty && !identical(_registeredIn, deps)) {
      // Switched to a different Deps instance entirely - whatever we
      // registered belongs to the old one, not this one.
      _releaseKeys(_registeredInEntry, _registeredIn, _registeredKeys);
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

    _releaseKeys(entry, deps, _registeredKeys.difference(currentKeys));
    _retainKeys(entry, currentKeys.difference(_registeredKeys));
    deps.addAll(currentByKey.values);

    _registeredKeys = currentKeys;
    _registeredIn = deps;
    _registeredInEntry = entry;
  }

  /// Removes [keys] from [deps] - or, when [entry] is non-null (i.e. [deps]
  /// is a shared scope), only once none of [entry]'s other holders still
  /// register that key.
  static void _releaseKeys(
    _SharedDepsEntry? entry,
    Deps deps,
    Iterable<DependencyKey> keys,
  ) {
    if (entry == null) {
      keys.forEach(deps.remove);
      return;
    }
    for (final key in keys) {
      final remaining = (entry.registrationRefCounts[key] ?? 1) - 1;
      if (remaining <= 0) {
        entry.registrationRefCounts.remove(key);
        deps.remove(key);
      } else {
        entry.registrationRefCounts[key] = remaining;
      }
    }
  }

  static void _retainKeys(
    _SharedDepsEntry? entry,
    Iterable<DependencyKey> keys,
  ) {
    if (entry == null) {
      return;
    }
    for (final key in keys) {
      entry.registrationRefCounts
          .update(key, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  @override
  void dispose() {
    final registeredIn = _registeredIn;
    final registeredKeys = _registeredKeys;
    final registeredInEntry = _registeredInEntry;
    final registry = _registry;
    final sharedKey = _sharedKeyHeld;

    if (registry != null) {
      // Deferred by a frame: if another DepsProvider mounts with the same
      // sharedKey before this runs - the common case for a same-frame
      // screen-transition handoff - it retains/acquires first, so this
      // release never actually reaches zero and the shared scope (and any
      // dependency both sides register) survives instead of being torn
      // down and immediately recreated.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _releaseKeys(registeredInEntry, registeredIn, registeredKeys);
        registry.release(sharedKey!);
      });
    } else {
      registeredKeys.forEach(registeredIn.remove);
      _ownedDeps?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inherited = context.getInheritedWidgetOfExactType<_DepsInherited>();
    final parentScope = inherited?.deps ?? globalDeps;
    _updateDeps(parentScope, inherited);
    _updateRegistrations();

    return _DepsInherited(
      deps: _deps!,
      registry: _ownRegistry,
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
    required this.registry,
  });

  final Deps deps;

  /// The owning [DepsProvider]'s registry of [_SharedDepsEntry]s, offered to
  /// its descendants for their own [DepsProvider.sharedKey] usage.
  final _SharedDepsRegistry registry;

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
