import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spyglass_bloc/flutter_spyglass_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class Counter extends Cubit<int> {
  Counter(super.initialState);
}

void main() {
  testWidgets(
      'rebuilds with the current state and on every emission by '
      'default', (tester) async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_) => Counter(0)))
      ..ensureResolved([Counter]);

    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: Builder(
            builder: (context) => BlocBuilder<Counter, int>(
              builder: (context, state) {
                builds++;
                return Text('$state');
              },
            ),
          ),
        ),
      ),
    );

    expect(builds, equals(1));
    expect(find.text('0'), findsOneWidget);

    deps.get<Counter>().emit(1);
    await tester.pumpAndSettle();

    expect(builds, equals(2));
    expect(find.text('1'), findsOneWidget);

    await deps.dispose();
  });

  testWidgets('buildWhen controls whether an emission triggers a rebuild',
      (tester) async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_) => Counter(0)))
      ..ensureResolved([Counter]);

    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: Builder(
            builder: (context) => BlocBuilder<Counter, int>(
              buildWhen: (previous, current) => current.isEven,
              builder: (context, state) {
                builds++;
                return Text('$state');
              },
            ),
          ),
        ),
      ),
    );

    expect(builds, equals(1));
    expect(find.text('0'), findsOneWidget);

    deps.get<Counter>().emit(1);
    await tester.pumpAndSettle();

    // Odd state - buildWhen says no rebuild, so the old text stays.
    expect(builds, equals(1));
    expect(find.text('0'), findsOneWidget);

    deps.get<Counter>().emit(2);
    await tester.pumpAndSettle();

    expect(builds, equals(2));
    expect(find.text('2'), findsOneWidget);

    await deps.dispose();
  });

  testWidgets('an explicit bloc is used instead of the one from Deps',
      (tester) async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_) => Counter(0)))
      ..ensureResolved([Counter]);
    final explicitCounter = Counter(100);

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: Builder(
            builder: (context) => BlocBuilder<Counter, int>(
              bloc: explicitCounter,
              builder: (context, state) => Text('$state'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('100'), findsOneWidget);

    explicitCounter.emit(101);
    await tester.pumpAndSettle();

    expect(find.text('101'), findsOneWidget);

    await deps.dispose();
    await explicitCounter.close();
  });

  testWidgets('rebuilds against a newly-registered bloc instance',
      (tester) async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_) => Counter(0)))
      ..ensureResolved([Counter]);

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: Builder(
            builder: (context) => BlocBuilder<Counter, int>(
              builder: (context, state) => Text('$state'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('0'), findsOneWidget);

    deps.replace(BlocDependency<Counter>((_) => Counter(42)));
    await tester.pumpAndSettle();

    expect(find.text('42'), findsOneWidget);

    deps.get<Counter>().emit(43);
    await tester.pumpAndSettle();

    expect(find.text('43'), findsOneWidget);

    await deps.dispose();
  });
}
