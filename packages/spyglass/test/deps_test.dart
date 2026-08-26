import 'package:spyglass/spyglass.dart';
import 'package:test/test.dart';

void main() {
  test('instant', () {
    deps
      ..add(Dependency<Bar>((deps) => Bar()))
      ..add(Dependency<Foo>((deps) => Foo(bar: deps.get())));

    expect(() => deps.get<Foo>(), returnsNormally);
  });

  test('observe mutable', () async {
    deps
      ..add(Dependency((deps) => Baz(label: 'first')))
      ..add(
        Dependency(
          (_) => Qux(baz: deps.get()),
          observe: const [Baz],
          update: (deps, oldValue) => oldValue..baz = deps.get(),
        ),
      );

    await Future<void>.delayed(const Duration(seconds: 1));

    deps.replace(Dependency.value(Baz(label: 'second')));

    expect(deps.get<Qux>().label, equals('second'));
  });

  test('observe immutable', () async {
    deps
      ..add(Dependency((deps) => Baz(label: 'first')))
      ..add(
        Dependency(
          (_) => Qux(baz: deps.get()),
          observe: const [Baz],
          update: (deps, oldValue) => Qux(baz: deps.get()),
        ),
      );

    await Future<void>.delayed(const Duration(seconds: 1));

    deps.replace(Dependency.value(Baz(label: 'second')));

    expect(deps.get<Qux>().label, equals('second'));
  });

  test('createObserver is only called once something actually watches',
      () async {
    var createObserverCalls = 0;
    var disposeCalls = 0;

    final scopeDeps = Deps.detached()
      ..add(
        Dependency<Bar>(
          (_) => Bar(),
          createObserver: (value) {
            createObserverCalls++;
            return _TrackingObserver(onDispose: () => disposeCalls++);
          },
        ),
      );

    // Plain reads - a pure "service locator" usage - shouldn't set up any
    // observation machinery at all.
    expect(scopeDeps.get<Bar>(), isA<Bar>());
    expect(scopeDeps.get<Bar>(), isA<Bar>());
    expect(createObserverCalls, equals(0));

    // Only track() should trigger it, and only once.
    final sub = scopeDeps.track<Bar>().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(createObserverCalls, equals(1));

    await sub.cancel();
    await scopeDeps.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(disposeCalls, equals(1));
  });

  test(
      'track() shares one observer across multiple '
      'subscribers to the same key', () async {
    var createObserverCalls = 0;

    final scopeDeps = Deps.detached()
      ..add(
        Dependency<Bar>(
          (_) => Bar(),
          createObserver: (value) {
            createObserverCalls++;
            return _TrackingObserver(onDispose: () {});
          },
        ),
      );

    final sub1 = scopeDeps.track<Bar>().listen((_) {});
    final sub2 = scopeDeps.track<Bar>().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(createObserverCalls, equals(1));

    await sub1.cancel();
    await sub2.cancel();
    await scopeDeps.dispose();
  });

  test(
      'trackInstance() never triggers observer creation, even '
      'with multiple subscribers', () async {
    var createObserverCalls = 0;

    final scopeDeps = Deps.detached()
      ..add(
        Dependency<Bar>(
          (_) => Bar(),
          createObserver: (value) {
            createObserverCalls++;
            return _TrackingObserver(onDispose: () {});
          },
        ),
      );

    final sub1 = scopeDeps.trackInstance<Bar>().listen((_) {});
    final sub2 = scopeDeps.trackInstance<Bar>().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(createObserverCalls, equals(0));

    await sub1.cancel();
    await sub2.cancel();
    await scopeDeps.dispose();
  });

  test('track() switches to a newly re-registered '
      'instance and stops reacting to the old one', () async {
    Dependency<Counter> makeCounter(int value) => Dependency<Counter>(
          (_) => Counter(value),
          createObserver: _CounterObserver.new,
        );

    final scopeDeps = Deps.detached()..add(makeCounter(1));

    final values = <int>[];
    final sub =
        scopeDeps.track<Counter>().listen((c) => values.add(c.value));
    await Future<void>.delayed(Duration.zero);

    final firstCounter = scopeDeps.get<Counter>()..set(2);
    await Future<void>.delayed(Duration.zero);

    scopeDeps.replace(makeCounter(100));
    await Future<void>.delayed(Duration.zero);

    // Mutating the now-replaced instance shouldn't reach the subscriber.
    firstCounter.set(999);
    await Future<void>.delayed(Duration.zero);

    scopeDeps.get<Counter>().set(200);
    await Future<void>.delayed(Duration.zero);

    expect(values, equals([1, 2, 100, 200]));

    await sub.cancel();
    await scopeDeps.dispose();
  });

  test(
      'DependencyObserver.dispose is called exactly once on replacement and '
      'once on removal', () async {
    final disposedLabels = <String>[];
    Dependency<Counter> makeCounter(String label, int value) =>
        Dependency<Counter>(
          (_) => Counter(value),
          createObserver: (c) =>
              _CounterObserver(c, onDispose: () => disposedLabels.add(label)),
        );

    final scopeDeps = Deps.detached()..add(makeCounter('first', 1));

    final sub = scopeDeps.track<Counter>().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(disposedLabels, isEmpty);

    scopeDeps.replace(makeCounter('second', 2));
    await Future<void>.delayed(Duration.zero);
    expect(disposedLabels, equals(['first']));

    await sub.cancel();
    await scopeDeps.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(disposedLabels, equals(['first', 'second']));
  });

  test('get() throws after Deps.dispose()', () async {
    final scopeDeps = Deps.detached()..add(Dependency<Bar>((_) => Bar()));
    expect(scopeDeps.get<Bar>(), isA<Bar>());

    await scopeDeps.dispose();

    expect(
      () => scopeDeps.get<Bar>(),
      throwsA(isA<DepsDisposedException>()),
    );
  });

  test('add() throws after Deps.dispose(), but remove() is a no-op',
      () async {
    final scopeDeps = Deps.detached()..add(Dependency<Bar>((_) => Bar()));
    await scopeDeps.dispose();

    expect(
      () => scopeDeps.add(Dependency<Foo>((_) => Foo(bar: Bar()))),
      throwsA(isA<DepsDisposedException>()),
    );
    expect(() => scopeDeps.remove<Bar>(), returnsNormally);
  });

  test('get() throws DependencyNotRegisteredException for an unknown key, '
      'but tryGet() returns null', () {
    final scopeDeps = Deps.detached();

    expect(
      () => scopeDeps.get<Bar>(),
      throwsA(isA<DependencyNotRegisteredException>()),
    );
    expect(scopeDeps.tryGet<Bar>(), isNull);
  });

  test('peek() returns the current value without triggering creation', () {
    var created = false;
    final scopeDeps = Deps.detached()
      ..add(Dependency<Bar>((_) {
        created = true;
        return Bar();
      }));

    expect(scopeDeps.peek<Bar>(), isNull);
    expect(created, isFalse);

    final value = scopeDeps.get<Bar>();
    expect(created, isTrue);
    expect(scopeDeps.peek<Bar>(), same(value));
  });

  test('DependencyCycleException is thrown for a self-referential create()',
      () {
    final scopeDeps = Deps.detached()
      ..add(Dependency<Bar>((deps) {
        deps.get<Bar>();
        return Bar();
      }));

    expect(
      () => scopeDeps.get<Bar>(),
      throwsA(isA<DependencyCycleException>()),
    );
  });

  test('add() leaves the existing value in place when cacheKey matches '
      '(including both being null), and replaces when it differs', () {
    final scopeDeps = Deps.detached()..add(Dependency<Bar>((_) => Bar()));
    final first = scopeDeps.get<Bar>();

    // No cacheKey on either side - null == null - left alone.
    scopeDeps.add(Dependency<Bar>((_) => Bar()));
    expect(scopeDeps.get<Bar>(), same(first));

    // Newly-specified, non-null cacheKey differs from the existing null -
    // replaced.
    scopeDeps.add(Dependency<Bar>((_) => Bar(), cacheKey: 'v1'));
    final second = scopeDeps.get<Bar>();
    expect(second, isNot(same(first)));

    // Same cacheKey as what's already there - left alone.
    scopeDeps.add(Dependency<Bar>((_) => Bar(), cacheKey: 'v1'));
    expect(scopeDeps.get<Bar>(), same(second));

    // Different cacheKey - replaced.
    scopeDeps.add(Dependency<Bar>((_) => Bar(), cacheKey: 'v2'));
    expect(scopeDeps.get<Bar>(), isNot(same(second)));
  });

  test('replace() always replaces, even when cacheKey matches', () {
    final scopeDeps = Deps.detached()
      ..add(Dependency<Bar>((_) => Bar(), cacheKey: 'v1'));
    final first = scopeDeps.get<Bar>();

    scopeDeps.replace(Dependency<Bar>((_) => Bar(), cacheKey: 'v1'));

    expect(scopeDeps.get<Bar>(), isNot(same(first)));
  });
}

class _TrackingObserver extends DependencyObserver<Bar> {
  _TrackingObserver({required this.onDispose});

  final void Function() onDispose;

  @override
  Future<void> dispose() async => onDispose();
}

/// A minimal mutable, observable value - the pure-Dart stand-in for a
/// ChangeNotifier, used to test [DependencyObserver.notifyStateChanged]
/// without depending on Flutter.
class Counter {
  Counter(this.value);

  int value;
  final List<void Function()> _listeners = [];

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) =>
      _listeners.remove(listener);

  void set(int newValue) {
    value = newValue;
    for (final listener in [..._listeners]) {
      listener();
    }
  }
}

class _CounterObserver extends DependencyObserver<Counter> {
  _CounterObserver(this.counter, {this.onDispose}) {
    counter.addListener(_onChange);
  }

  final Counter counter;
  final void Function()? onDispose;

  void _onChange() => notifyStateChanged();

  @override
  Future<void> dispose() async {
    counter.removeListener(_onChange);
    onDispose?.call();
  }
}

class Bar {}

class Foo {
  Foo({required this.bar});

  final Bar bar;
}

class Baz {
  Baz({required this.label});

  final String label;
}

class Qux {
  Qux({required this.baz});

  Baz baz;

  String get label => baz.label;
}
