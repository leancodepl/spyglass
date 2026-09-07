import 'package:flutter/widgets.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    "DepsProvider's internal InheritedWidget surfaces the live scope's "
    'diagnostics tree',
    (tester) async {
      final deps = Deps.detached()..add(Dependency<Bar>((_, __) => Bar()));

      await tester.pumpWidget(
        DepsProvider(
          deps: deps,
          introduceScope: false,
          child: const SizedBox(),
        ),
      );

      final inheritedWidget = tester.widget(
        find.byElementPredicate(
          (element) => element.widget.runtimeType.toString() ==
              '_DepsInherited',
        ),
      );
      final tree = inheritedWidget.toDiagnosticsNode().toStringDeep();

      expect(tree, contains('not yet resolved'));

      deps.get<Bar>();
      await tester.pump();

      final updatedTree = tester
          .widget(
            find.byElementPredicate(
              (element) => element.widget.runtimeType.toString() ==
                  '_DepsInherited',
            ),
          )
          .toDiagnosticsNode()
          .toStringDeep();
      expect(updatedTree, contains('resolved'));

      await deps.dispose();
    },
  );

  test('toDiagnosticsNode() prefers debugLabel over identity in its name',
      () {
    final deps = Deps.detached(debugLabel: 'AuthScope');

    expect(deps.toDiagnosticsNode().toStringDeep(), contains('AuthScope'));

    deps.dispose();
  });

  test(
    'toDiagnosticsNode() shows an unresolved dependency, then resolved '
    'after get()',
    () {
      final deps = Deps.detached()..add(Dependency<Bar>((_, __) => Bar()));

      expect(
        deps.toDiagnosticsNode().toStringDeep(),
        contains('not yet resolved'),
      );

      deps.get<Bar>();

      final tree = deps.toDiagnosticsNode().toStringDeep();
      expect(tree, isNot(contains('not yet resolved')));
      expect(tree, contains('resolved'));

      deps.dispose();
    },
  );

  test(
    'toDiagnosticsNode() nests fork()ed child scopes only when '
    'spyglassDiagnosticsMode is enabled',
    () {
      final root = Deps.detached();
      final child = root.fork();

      final tree = root.toDiagnosticsNode().toStringDeep();

      if (spyglassDiagnosticsMode) {
        expect(tree, contains('child scope'));
      } else {
        expect(tree, isNot(contains('child scope')));
      }

      child.dispose();
      root.dispose();
    },
  );

  test('toDiagnosticsNode() flags a disposed scope', () async {
    final deps = Deps.detached();
    await deps.dispose();

    expect(deps.toDiagnosticsNode().toStringDeep(), contains('disposed'));
  });

  test('toDiagnosticsNode() flags whether a dependency was registered '
      'standalone or as part of a Module', () {
    final deps = Deps.detached()
      ..add(Module([Dependency<Bar>((_, __) => Bar())], debugLabel: 'BarModule'))
      ..add(Dependency<Foo>((_, __) => Foo()));

    final tree = deps.toDiagnosticsNode().toStringDeep();

    expect(tree, contains("part of Module('BarModule')"));
    expect(tree, contains('standalone'));

    deps.dispose();
  });
}

class Bar {}

class Foo {}
