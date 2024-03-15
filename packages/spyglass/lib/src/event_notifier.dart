import 'dart:async';

import 'package:meta/meta.dart';

abstract class EventNotifier<E> {
  EventNotifier();

  final _controller = StreamController<E>.broadcast();

  Stream<E> get events => _controller.stream;

  @protected
  @nonVirtual
  void notify(E event) {
    _controller.add(event);
  }

  @mustCallSuper
  Future<void> dispose() {
    return _controller.close();
  }
}
