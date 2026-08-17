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

    deps.add(Dependency.value(Baz(label: 'second')));

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

    deps.add(Dependency.value(Baz(label: 'second')));

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

    // Only observing with observeState:true should trigger it, and only once.
    final sub = scopeDeps.observe<Bar>(observeState: true).listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(createObserverCalls, equals(1));

    await sub.cancel();
    await scopeDeps.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(disposeCalls, equals(1));
  });
}

class _TrackingObserver extends DependencyObserver<Bar> {
  _TrackingObserver({required this.onDispose});

  final void Function() onDispose;

  @override
  Future<void> dispose() async => onDispose();
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
