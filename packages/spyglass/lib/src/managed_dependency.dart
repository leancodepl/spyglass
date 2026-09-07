import 'dart:async';

import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

import 'dependency.dart';
import 'dependency_observer.dart';
import 'deps.dart';
import 'deps_events.dart';
import 'deps_exceptions.dart';
import 'deps_reader.dart';
import 'types.dart';

/// This class helps manage lifecycle of a single dependency. It is tightly
/// coupled with [Deps]. It's an internal structure and it should never be
/// exposed as part of the public API.
@internal
class ManagedDependency<T extends Object> {
  ManagedDependency(this.dependency, this.deps, this.origin);

  final Dependency<T> dependency;
  final Deps deps;

  /// The [Registerable] that was actually passed to
  /// [Deps.add]/[Deps.addAll] - see [DependencyDiagnostics.origin].
  final Registerable origin;

  DependencyKey get key => dependency.key;

  /// This dependency's own value stream, shared by every subscriber that
  /// watches this key with [Deps.watch] - see also [watch] below. Created
  /// lazily, on the first call to [watch], so a dependency that's only ever
  /// plain-read via [Deps.get] - the common "just a service locator" case -
  /// never pays for a [DependencyObserver] or a [BehaviorSubject] it doesn't
  /// need.
  BehaviorSubject<T>? _controller;
  StreamSubscription<void>? _observeSubscription;
  T? _currentValue;

  /// One observer for the current [_currentValue], not one per subscriber -
  /// see [DependencyObserver]. Only created once [watch] has been called at
  /// least once (see [_controller]); recreated whenever [_currentValue]
  /// itself is replaced (either by re-registration or by a reactive
  /// [_runCreate] run).
  DependencyObserver<T>? _stateObserver;
  bool _debugCreateCalled = false;
  bool _isDisposed = false;

  /// The set of keys [Dependency.create] read via [DepsReader.watchInstance]
  /// on its last run - i.e. what [_observeSubscription] is currently
  /// subscribed to. Rediscovered on every run of [_runCreate], since which
  /// keys it reads can depend on `oldValue` and change between runs.
  Set<DependencyKey> _trackedKeys = const {};

  /// The currently resolved value, if any - without triggering creation.
  /// Package-internal - not `_`-private only because [Deps.peek] and
  /// [Deps.debugOwnDependencies] (a different library, now that spyglass's
  /// source is split across files) need to read it too.
  @internal
  T? get currentValue => _currentValue;

  /// No-op unless [watch] has already been called at least once for this
  /// dependency - see [_controller].
  void _attachStateObserverIfTracked(T value) {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    _stateObserver = dependency.createObserver(value)
      ?..attach(() => controller.add(value));
  }

  void _ensureInitialized() {
    if (_isDisposed) {
      throw DepsDisposedException(key: key);
    }
    if (_currentValue != null) {
      return;
    }
    if (_debugCreateCalled) {
      throw DependencyCycleException(key);
    }
    _debugCreateCalled = true;
    _runCreate();
  }

  /// Runs [Dependency.create], applies its result, and re-subscribes to
  /// whatever it read via [DepsReader.watchInstance] this time - called
  /// once for the initial value (with `oldValue: null`), and again every
  /// time one of the keys tracked on the *previous* run is re-registered
  /// under a new instance.
  void _runCreate() {
    if (_isDisposed) {
      return;
    }

    final reader = _TrackingDepsReader(deps);
    final newValue = dependency.create(reader, _currentValue);
    _applyTrackedKeys(reader.tracked);

    if (newValue != _currentValue) {
      final oldObserver = _stateObserver;
      _currentValue = newValue;
      _stateObserver = null;
      unawaited(oldObserver?.dispose());
      _attachStateObserverIfTracked(newValue);
      _controller?.add(newValue);
      // reason: ManagedDependency and Deps work in tandem
      // ignore: invalid_use_of_protected_member
      deps.notify(DependencyChanged(key: key));
    }
  }

  void _applyTrackedKeys(Set<DependencyKey> newTracked) {
    if (_sameKeys(newTracked, _trackedKeys)) {
      // Nothing [Dependency.create] reads changed since last time - the
      // existing subscription (if any) is still exactly right.
      return;
    }
    _trackedKeys = newTracked;
    unawaited(_observeSubscription?.cancel());
    _observeSubscription = newTracked.isEmpty
        ? null
        : deps.watchMany(newTracked.toList()).listen((_) => _runCreate());
  }

  static bool _sameKeys(Set<DependencyKey> a, Set<DependencyKey> b) =>
      a.length == b.length && a.containsAll(b);

  T resolve() {
    _ensureInitialized();
    return switch (_currentValue) {
      final T value => value,
      null => throw StateError('Initialization error. This is a bug.'),
    };
  }

  T? tryResolve() {
    _ensureInitialized();
    return _currentValue;
  }

  Stream<T> watch() {
    _ensureInitialized();
    var controller = _controller;
    if (controller == null) {
      controller = _controller = BehaviorSubject<T>();
      _attachStateObserverIfTracked(_currentValue!);
      controller.add(_currentValue!);
    }
    return controller.stream;
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _observeSubscription?.cancel();
    await _controller?.close();
    await _stateObserver?.dispose();
    if ((dependency.dispose, _currentValue)
        case (final dispose?, final value?)) {
      final resolvedValue = value;
      await dispose(resolvedValue);
    }
  }
}

/// The [DepsReader] passed to [Dependency.create] - a thin wrapper around
/// the real [Deps] that records every key read via [watchInstance] into
/// [tracked], so [ManagedDependency._applyTrackedKeys] can subscribe to
/// exactly those keys afterward. [get] is a plain, unrecorded passthrough.
class _TrackingDepsReader implements DepsReader {
  _TrackingDepsReader(this._deps);

  final Deps _deps;
  final Set<DependencyKey> tracked = {};

  @override
  T get<T extends Object>([DependencyKey? key]) => _deps.get<T>(key);

  @override
  T watchInstance<T extends Object>([DependencyKey? key]) {
    tracked.add(key ?? T);
    return _deps.get<T>(key);
  }
}
