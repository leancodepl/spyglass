import 'package:spyglass/spyglass.dart';
import 'package:test/test.dart';

void main() {
  test('pure', () {
    globalDeps.add(
      Dependency(
        create: (deps) async {
          final value = await deps.getAsync<int>();
          return value > 10;
        },
      ),
    );

    Future<void>.delayed(const Duration(seconds: 3), () {
      globalDeps.add(Dependency<int>.value(5));
    });

    expect(globalDeps.getAsync<bool>(), completion(isFalse));
  });

  test('instant', () {
    deps
      ..add(Dependency<Bar>(create: (deps) => Bar()))
      ..add(Dependency<Foo>(create: (deps) => Foo(bar: deps.get())));

    expect(() => deps.get<Foo>(), returnsNormally);
  });

  test('observe mutable', () async {
    deps
      ..add(Dependency(create: (deps) => Baz(label: 'first')))
      ..add(
        Dependency(
          create: (deps) => Qux(baz: deps.get()),
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
      ..add(Dependency(create: (deps) => Baz(label: 'first')))
      ..add(
        Dependency(
          create: (deps) => Qux(baz: deps.get()),
          observe: const [Baz],
          update: (deps, oldValue) => Qux(baz: deps.get()),
        ),
      );

    await Future<void>.delayed(const Duration(seconds: 1));

    deps.add(Dependency.value(Baz(label: 'second')));

    expect(deps.get<Qux>().label, equals('second'));
  });

  test('eager resolves to expected value', () {
    deps.add(Dependency(lazy: false, create: (deps) => Bar()));

    expect(deps.get<Bar>(), isA<Bar>());
  });

  test('eager with unresolved dependency throws when adding', () {
    deps.add(Dependency(create: (deps) async {
      await Future<void>.delayed(const Duration(seconds: 1));
      return Bar();
    }));

    expect(
      () => deps
          .add(Dependency(lazy: false, create: (deps) => Foo(bar: deps.get()))),
      throwsStateError,
    );
  });
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
