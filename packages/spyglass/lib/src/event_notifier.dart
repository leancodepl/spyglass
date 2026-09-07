import 'dart:async';

import 'package:meta/meta.dart';

/// A minimal broadcast-event base - `Deps` extends this for its own
/// `DepsEvent` stream. Package-internal; not exposed as part of the public
/// API.
@internal
abstract class EventNotifier<E> {
  /// Creates an [EventNotifier] with a fresh, empty [events] stream.
  EventNotifier();

  final _controller = StreamController<E>.broadcast();

  /// Broadcast stream of every event passed to [notify].
  Stream<E> get events => _controller.stream;

  /// Emits [event] to every current subscriber of [events].
  @protected
  @nonVirtual
  void notify(E event) {
    _controller.add(event);
  }

  /// Closes [events] - subclasses overriding this should call `super`.
  @mustCallSuper
  Future<void> dispose() {
    return _controller.close();
  }
}
