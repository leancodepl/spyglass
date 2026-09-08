import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spyglass_bloc/flutter_spyglass_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class Counter extends Cubit<int> {
  Counter(super.initialState);
}

void main() {
  testWidgets('rebuilds with the selected value and only when it changes', (
    tester,
  ) async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_, __) => Counter(0)))
      ..ensureResolved([Counter]);

    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: Builder(
            builder: (context) => BlocSelector<Counter, int, bool>(
              selector: (state) => state.isEven,
              builder: (context, isEven) {
                builds++;
                return Text('$isEven');
              },
            ),
          ),
        ),
      ),
    );

    expect(builds, equals(1));
    expect(find.text('true'), findsOneWidget);

    // Still even -> selected value unchanged -> no rebuild.
    deps.get<Counter>().emit(2);
    await tester.pumpAndSettle();

    expect(builds, equals(1));
    expect(find.text('true'), findsOneWidget);

    // Odd -> selected value changes -> rebuild.
    deps.get<Counter>().emit(3);
    await tester.pumpAndSettle();

    expect(builds, equals(2));
    expect(find.text('false'), findsOneWidget);

    await deps.dispose();
  });

  testWidgets('an explicit bloc is used instead of the one from Deps', (
    tester,
  ) async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_, __) => Counter(0)))
      ..ensureResolved([Counter]);
    final explicitCounter = Counter(100);

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: Builder(
            builder: (context) => BlocSelector<Counter, int, int>(
              bloc: explicitCounter,
              selector: (state) => state,
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

  testWidgets('rebuilds against a newly-registered bloc instance', (
    tester,
  ) async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_, __) => Counter(0)))
      ..ensureResolved([Counter]);

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: Builder(
            builder: (context) => BlocSelector<Counter, int, int>(
              selector: (state) => state,
              builder: (context, state) => Text('$state'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('0'), findsOneWidget);

    deps.replace(BlocDependency<Counter>((_, __) => Counter(42)));
    await tester.pumpAndSettle();

    expect(find.text('42'), findsOneWidget);

    deps.get<Counter>().emit(43);
    await tester.pumpAndSettle();

    expect(find.text('43'), findsOneWidget);

    await deps.dispose();
  });
}
