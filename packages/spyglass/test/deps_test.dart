import 'package:spyglass/spyglass.dart';
import 'package:test/test.dart';

void main() {
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
