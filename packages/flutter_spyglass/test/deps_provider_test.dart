import 'package:flutter/material.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'mutating one dependency does not rebuild a widget observing a '
      'different one', (tester) async {
    var buildsA = 0;
    var buildsB = 0;

    final deps = Deps.detached()
      ..add(ChangeNotifierDependency<CounterA>((_, __) => CounterA(0)))
      ..add(ChangeNotifierDependency<CounterB>((_, __) => CounterB(0)))
      ..ensureResolved([CounterA, CounterB]);

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider.deps(
          deps,
          child: Column(
            children: [
              Builder(builder: (context) {
                buildsA++;
                return Text('A:${context.watch<CounterA>().value}');
              }),
              Builder(builder: (context) {
                buildsB++;
                return Text('B:${context.watch<CounterB>().value}');
              }),
            ],
          ),
        ),
      ),
    );

    expect(buildsA, equals(1));
    expect(buildsB, equals(1));
    expect(find.text('A:0'), findsOneWidget);
    expect(find.text('B:0'), findsOneWidget);

    deps.get<CounterA>().increment();
    await tester.pumpAndSettle();

    expect(buildsA, equals(2));
    expect(buildsB, equals(1));
    expect(find.text('A:1'), findsOneWidget);
    expect(find.text('B:0'), findsOneWidget);

    await deps.dispose();
  });

  testWidgets(
      'unmounting one shared watcher does not affect the remaining '
      'watchers of the same dependency', (tester) async {
    final deps = Deps.detached()
      ..add(ChangeNotifierDependency<Counter>((_, __) => Counter(0)))
      ..ensureResolved([Counter]);

    Widget watcher(int index) => Builder(builder: (context) {
          return Text('$index:${context.watch<Counter>().value}');
        });

    Widget buildTree(bool includeThird) => MaterialApp(
          home: DepsProvider.deps(
            deps,
            child: Column(
              children: [
                watcher(0),
                watcher(1),
                if (includeThird) watcher(2),
              ],
            ),
          ),
        );

    await tester.pumpWidget(buildTree(true));
    expect(find.text('0:0'), findsOneWidget);
    expect(find.text('1:0'), findsOneWidget);
    expect(find.text('2:0'), findsOneWidget);

    // Unmount the third watcher; the other two stay in the tree.
    await tester.pumpWidget(buildTree(false));
    expect(find.text('2:0'), findsNothing);

    deps.get<Counter>().increment();
    await tester.pumpAndSettle();

    expect(find.text('0:1'), findsOneWidget);
    expect(find.text('1:1'), findsOneWidget);
    expect(find.text('2:1'), findsNothing);

    await deps.dispose();
  });

  testWidgets(
      'the same type can be watched with different observeState values '
      'at once', (tester) async {
    final deps = Deps.detached()
      ..add(ChangeNotifierDependency<Counter>((_, __) => Counter(0)))
      ..ensureResolved([Counter]);

    var trueBuilds = 0;
    var falseBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider.deps(
          deps,
          child: Column(
            children: [
              Builder(builder: (context) {
                trueBuilds++;
                return Text('true:${context.watch<Counter>().value}');
              }),
              Builder(builder: (context) {
                falseBuilds++;
                return Text('false:${context.watchInstance<Counter>().value}');
              }),
            ],
          ),
        ),
      ),
    );

    expect(trueBuilds, equals(1));
    expect(falseBuilds, equals(1));

    // An internal ChangeNotifier tick - only the observeState:true watcher
    // should react. Settling a dependency-observation change can take more
    // than one pump (the value flows through a couple of internal stream
    // hops before it reaches the widget), same as dispose_benchmark.dart's
    // multi-pump drain for a similar reason - use pumpAndSettle rather than
    // guessing a pump count.
    deps.get<Counter>().increment();
    await tester.pumpAndSettle();

    expect(trueBuilds, equals(2));
    expect(falseBuilds, equals(1));
    expect(find.text('true:1'), findsOneWidget);
    expect(find.text('false:0'), findsOneWidget);

    // A full replacement is a registration-level change - both should react.
    // add() alone wouldn't do it now: same key, no cacheKey on either side,
    // so add() would leave the existing Counter in place. replace() is the
    // explicit "swap this out" call.
    deps.replace(ChangeNotifierDependency<Counter>((_, __) => Counter(100)));
    await tester.pumpAndSettle();

    expect(trueBuilds, equals(3));
    expect(falseBuilds, equals(2));
    expect(find.text('true:100'), findsOneWidget);
    expect(find.text('false:100'), findsOneWidget);

    await deps.dispose();
  });

  testWidgets('multiple selectors on the same dependency rebuild independently',
      (tester) async {
    final deps = Deps.detached()
      ..add(ChangeNotifierDependency<Pair>((_, __) => Pair(0, 100)))
      ..ensureResolved([Pair]);

    var aBuilds = 0;
    var bBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider.deps(
          deps,
          child: Column(
            children: [
              Builder(builder: (context) {
                aBuilds++;
                final a = context.select<Pair, int>((p) => p.a);
                return Text('a:$a');
              }),
              Builder(builder: (context) {
                bBuilds++;
                final b = context.select<Pair, int>((p) => p.b);
                return Text('b:$b');
              }),
            ],
          ),
        ),
      ),
    );

    expect(aBuilds, equals(1));
    expect(bBuilds, equals(1));

    // Only `a` changes - only the `a` selector's watcher should rebuild.
    deps.get<Pair>().setA(1);
    await tester.pumpAndSettle();

    expect(aBuilds, equals(2));
    expect(bBuilds, equals(1));
    expect(find.text('a:1'), findsOneWidget);
    expect(find.text('b:100'), findsOneWidget);

    // Only `b` changes - only the `b` selector's watcher should rebuild.
    deps.get<Pair>().setB(200);
    await tester.pumpAndSettle();

    expect(aBuilds, equals(2));
    expect(bBuilds, equals(2));
    expect(find.text('b:200'), findsOneWidget);

    await deps.dispose();
  });

  testWidgets(
      'mutating a dependency after its watcher unmounted does not throw',
      (tester) async {
    final deps = Deps.detached()
      ..add(ChangeNotifierDependency<Counter>((_, __) => Counter(0)))
      ..ensureResolved([Counter]);

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider.deps(
          deps,
          child: Builder(
            builder: (context) => Text('${context.watch<Counter>().value}'),
          ),
        ),
      ),
    );

    await tester.pumpWidget(const SizedBox());

    expect(() => deps.get<Counter>().increment(), returnsNormally);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await deps.dispose();
  });

  testWidgets(
      'a key present in both the old and new register list is left alone, '
      'not recreated', (tester) async {
    final deps = Deps.detached();

    Widget buildTree(int instanceId) => MaterialApp(
          home: DepsProvider.deps(
            deps,
            register: [
              Dependency<Marker>((_, __) => Marker(instanceId)),
            ],
            child: const SizedBox(),
          ),
        );

    await tester.pumpWidget(buildTree(1));
    final firstInstance = deps.get<Marker>();
    expect(firstInstance.instanceId, equals(1));

    // A structurally new Dependency<Marker>, but the same key (Marker) -
    // should NOT replace the already-registered instance.
    await tester.pumpWidget(buildTree(2));

    expect(deps.get<Marker>(), same(firstInstance));
    expect(deps.get<Marker>().instanceId, equals(1));

    await tester.pumpWidget(const SizedBox());
    await deps.dispose();
  });

  testWidgets(
      'a changed cacheKey in register forces a fresh instance under the '
      'same key', (tester) async {
    final deps = Deps.detached();

    Widget buildTree(int tenantId) => MaterialApp(
          home: DepsProvider.deps(
            deps,
            register: [
              Dependency<Marker>((_, __) => Marker(tenantId),
                  cacheKey: tenantId),
            ],
            child: const SizedBox(),
          ),
        );

    await tester.pumpWidget(buildTree(1));
    final firstInstance = deps.get<Marker>();
    expect(firstInstance.instanceId, equals(1));

    // Same cacheKey (tenantId unchanged) - a structurally new Dependency,
    // but left alone, same as when there's no cacheKey at all.
    await tester.pumpWidget(buildTree(1));
    expect(deps.get<Marker>(), same(firstInstance));

    // Different cacheKey - forces a fresh instance even though the key
    // (Marker) hasn't changed.
    await tester.pumpWidget(buildTree(2));
    expect(deps.get<Marker>(), isNot(same(firstInstance)));
    expect(deps.get<Marker>().instanceId, equals(2));

    await tester.pumpWidget(const SizedBox());
    await deps.dispose();
  });

  testWidgets(
      'a key removed from register is disposed; a key added to register '
      'is created', (tester) async {
    final deps = Deps.detached();
    final disposed = <String>[];

    Widget buildTree({required bool includeA, required bool includeB}) =>
        MaterialApp(
          home: DepsProvider.deps(
            deps,
            register: [
              if (includeA)
                Dependency<MarkerA>(
                  (_, __) => MarkerA(),
                  dispose: (_) => disposed.add('A'),
                ),
              if (includeB)
                Dependency<MarkerB>(
                  (_, __) => MarkerB(),
                  dispose: (_) => disposed.add('B'),
                ),
            ],
            child: const SizedBox(),
          ),
        );

    await tester.pumpWidget(buildTree(includeA: true, includeB: false));
    deps.ensureResolved([MarkerA]);
    expect(deps.isRegistered<MarkerA>(), isTrue);
    expect(deps.isRegistered<MarkerB>(), isFalse);

    // Drop A, add B.
    await tester.pumpWidget(buildTree(includeA: false, includeB: true));
    await tester.pump();
    deps.ensureResolved([MarkerB]);

    expect(deps.isRegistered<MarkerA>(), isFalse);
    expect(deps.isRegistered<MarkerB>(), isTrue);
    expect(disposed, equals(['A']));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(disposed, equals(['A', 'B']));

    await deps.dispose();
  });

  testWidgets(
      'DepsProviders sharing a sharedKey resolve to the same scope, created '
      'once and disposed once the last one unmounts', (tester) async {
    Deps? scopeA;
    Deps? scopeB;

    Widget buildTree({required bool includeA, required bool includeB}) =>
        MaterialApp(
          home: DepsProvider(
            child: Column(
              children: [
                if (includeA)
                  DepsProvider.shared(
                    'flow',
                    key: const ValueKey('a'),
                    child: Builder(builder: (context) {
                      scopeA = DepsProvider.of(context);
                      return const SizedBox();
                    }),
                  ),
                if (includeB)
                  DepsProvider.shared(
                    'flow',
                    key: const ValueKey('b'),
                    child: Builder(builder: (context) {
                      scopeB = DepsProvider.of(context);
                      return const SizedBox();
                    }),
                  ),
              ],
            ),
          ),
        );

    await tester.pumpWidget(buildTree(includeA: true, includeB: true));
    expect(scopeA, isNotNull);
    expect(scopeA, same(scopeB));
    final scope = scopeA!;
    expect(scope.isDisposed, isFalse);

    // Unmount A - B still references the shared scope, so it must survive.
    await tester.pumpWidget(buildTree(includeA: false, includeB: true));
    await tester.pump();
    expect(scope.isDisposed, isFalse);

    // Unmount B too - nothing references it any more.
    await tester.pumpWidget(buildTree(includeA: false, includeB: false));
    await tester.pump();
    expect(scope.isDisposed, isTrue);
  });

  testWidgets(
      'a dependency registered by more than one sharedKey provider is not '
      'disposed until none of them still register it', (tester) async {
    final disposed = <String>[];
    Deps? scope;

    Registerable markerDependency() => Dependency<Marker>(
          (_, __) => Marker(1),
          dispose: (_) => disposed.add('marker'),
        );

    Widget buildTree({required bool includeA, required bool includeB}) =>
        MaterialApp(
          home: DepsProvider(
            child: Column(
              children: [
                if (includeA)
                  DepsProvider.shared(
                    'flow',
                    key: const ValueKey('a'),
                    register: [markerDependency()],
                    child: Builder(builder: (context) {
                      scope = DepsProvider.of(context);
                      return const SizedBox();
                    }),
                  ),
                if (includeB)
                  DepsProvider.shared(
                    'flow',
                    key: const ValueKey('b'),
                    register: [markerDependency()],
                    child: const SizedBox(),
                  ),
              ],
            ),
          ),
        );

    await tester.pumpWidget(buildTree(includeA: true, includeB: true));
    final marker = scope!.get<Marker>();

    // Unmount A - B still lists the same key in its own register, so the
    // dependency it describes must survive.
    await tester.pumpWidget(buildTree(includeA: false, includeB: true));
    await tester.pump();
    expect(disposed, isEmpty);
    expect(scope!.get<Marker>(), same(marker));

    // Unmount B too - nothing registers it any more.
    await tester.pumpWidget(buildTree(includeA: false, includeB: false));
    await tester.pump();
    expect(disposed, equals(['marker']));
  });

  testWidgets(
      'a same-frame handoff between two sharedKey providers reuses the '
      'scope and its dependencies instead of recreating them', (tester) async {
    final disposed = <String>[];
    Deps? scope;

    Registerable markerDependency() => Dependency<Marker>(
          (_, __) => Marker(1),
          dispose: (_) => disposed.add('marker'),
        );

    Widget buildTree(Key key) => MaterialApp(
          home: DepsProvider(
            child: DepsProvider.shared(
              'flow',
              key: key,
              register: [markerDependency()],
              child: Builder(builder: (context) {
                scope = DepsProvider.of(context);
                return const SizedBox();
              }),
            ),
          ),
        );

    await tester.pumpWidget(buildTree(const ValueKey('a')));
    final originalScope = scope!;
    final marker = originalScope.get<Marker>();

    // A different key at the same slot forces a real unmount of 'a' and
    // mount of 'b' within this single pumpWidget call, rather than an
    // in-place update of one persisting element.
    await tester.pumpWidget(buildTree(const ValueKey('b')));
    await tester.pump();

    expect(scope, same(originalScope));
    expect(originalScope.isDisposed, isFalse);
    expect(originalScope.get<Marker>(), same(marker));
    expect(disposed, isEmpty);
  });

  testWidgets(
      'sharedKey providers with no ancestor DepsProvider still share a scope',
      (tester) async {
    Deps? scopeA;
    Deps? scopeB;

    Widget buildTree({required bool includeA, required bool includeB}) =>
        MaterialApp(
          home: Column(
            children: [
              if (includeA)
                DepsProvider.shared(
                  'no-ancestor-flow',
                  key: const ValueKey('a'),
                  child: Builder(builder: (context) {
                    scopeA = DepsProvider.of(context);
                    return const SizedBox();
                  }),
                ),
              if (includeB)
                DepsProvider.shared(
                  'no-ancestor-flow',
                  key: const ValueKey('b'),
                  child: Builder(builder: (context) {
                    scopeB = DepsProvider.of(context);
                    return const SizedBox();
                  }),
                ),
            ],
          ),
        );

    await tester.pumpWidget(buildTree(includeA: true, includeB: true));
    expect(scopeA, isNotNull);
    expect(scopeA, same(scopeB));
    final scope = scopeA!;

    await tester.pumpWidget(buildTree(includeA: false, includeB: false));
    await tester.pump();
    expect(scope.isDisposed, isTrue);
  });
}

class CounterA extends ChangeNotifier {
  CounterA(this._value);
  int _value;
  int get value => _value;
  void increment() {
    _value++;
    notifyListeners();
  }
}

class CounterB extends ChangeNotifier {
  CounterB(this._value);
  int _value;
  int get value => _value;
  void increment() {
    _value++;
    notifyListeners();
  }
}

class Counter extends ChangeNotifier {
  Counter(this._value);
  int _value;
  int get value => _value;
  void increment() {
    _value++;
    notifyListeners();
  }
}

class Pair extends ChangeNotifier {
  Pair(this._a, this._b);
  int _a;
  int _b;
  int get a => _a;
  int get b => _b;

  void setA(int value) {
    _a = value;
    notifyListeners();
  }

  void setB(int value) {
    _b = value;
    notifyListeners();
  }
}

class Marker {
  Marker(this.instanceId);
  final int instanceId;
}

class MarkerA {}

class MarkerB {}
