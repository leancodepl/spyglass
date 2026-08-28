import 'dart:async';

import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

import 'dependency.dart';
import 'dependency_observer.dart';
import 'deps.dart';
import 'deps_events.dart';
import 'deps_exceptions.dart';
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
  /// itself is replaced (either by re-registration or by the
  /// [Dependency.update] chain below).
  DependencyObserver<T>? _stateObserver;
  bool _debugCreateCalled = false;
  bool _isDisposed = false;

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
    _currentValue = dependency.create(deps);
    // reason: ManagedDependency and Deps work in tandem
    // ignore: invalid_use_of_protected_member
    deps.notify(DependencyChanged(key: key));

    if ((dependency.observe, dependency.update)
        case (final observe?, final update?)) {
      unawaited(_observeSubscription?.cancel());
      _observeSubscription = deps
          .watchMany(observe)
          .map((_) => update(deps, _currentValue!))
          .listen((newValue) {
        if (_isDisposed) {
          return;
        }
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
      });
    }
  }

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
