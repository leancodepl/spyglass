import 'package:spyglass/spyglass.dart';
import 'package:test/test.dart';

void main() {
  test('pure', () async {
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

  test('watch mutable', () async {
    deps
      ..add(Dependency(create: (deps) => Baz(label: 'first')))
      ..add(
        Dependency(
          create: (deps) => Qux(baz: deps.get()),
          when: (deps) => deps.watch<Baz>(),
          update: (deps, oldValue) => oldValue..baz = deps.get(),
        ),
      );

    await Future<void>.delayed(const Duration(seconds: 1));

    deps.add(Dependency.value(Baz(label: 'second')));

    expect(deps.get<Qux>().label, equals('second'));
  });

  test('watch immutable', () async {
    deps
      ..add(Dependency(create: (deps) => Baz(label: 'first')))
      ..add(
        Dependency(
          create: (deps) => Qux(baz: deps.get()),
          when: (deps) => deps.watch<Baz>(),
          update: (deps, oldValue) => Qux(baz: deps.get()),
        ),
      );

    await Future<void>.delayed(const Duration(seconds: 1));

    deps.add(Dependency.value(Baz(label: 'second')));

    expect(deps.get<Qux>().label, equals('second'));
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
