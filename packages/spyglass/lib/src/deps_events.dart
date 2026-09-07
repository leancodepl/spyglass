import 'package:equatable/equatable.dart';

import 'types.dart';

/// Event emitted by `Deps` when a dependency is registered, unregistered,
/// or changed.
sealed class DepsEvent {}

/// Event emitted by `Deps` when a dependency is registered. It does not mean
/// its value can be read by `Deps.get` if the dependency is asynchronous.
/// When an async dependency is resolved it will be followed by
/// a [DependencyChanged] event.
final class DependencyRegistered extends Equatable implements DepsEvent {
  /// Emitted when a dependency is registered under [key].
  const DependencyRegistered({
    required this.key,
  });

  /// The key of the dependency that was registered.
  final DependencyKey key;

  @override
  List<Object?> get props => [key];
}

/// Event emitted by `Deps` when a dependency is unregistered.
final class DependencyUnregistered extends Equatable implements DepsEvent {
  /// Emitted when the dependency registered under [key] is unregistered.
  const DependencyUnregistered({
    required this.key,
  });

  /// The key of the dependency that was unregistered.
  final DependencyKey key;

  @override
  List<Object?> get props => [key];
}

/// Event emitted by `Deps` when a dependency value is changed, i.e.
/// as a result of the `Dependency.create` callback (re-)running.
final class DependencyChanged extends Equatable implements DepsEvent {
  /// Emitted when the value registered under [key] changes.
  const DependencyChanged({
    required this.key,
  });

  /// The key of the dependency whose value changed.
  final DependencyKey key;

  @override
  List<Object?> get props => [key];
}
