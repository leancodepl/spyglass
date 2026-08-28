import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spyglass_bloc/flutter_spyglass_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class Counter extends Cubit<int> {
  Counter(super.initialState);
}

void main() {
  testWidgets('builds and listens for every emission by default',
      (tester) async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_) => Counter(0)))
      ..ensureResolved([Counter]);

    final seen = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: BlocConsumer<Counter, int>(
            listener: (context, state) => seen.add(state),
            builder: (context, state) => Text('$state'),
          ),
        ),
      ),
    );

    expect(find.text('0'), findsOneWidget);
    expect(seen, isEmpty);

    deps.get<Counter>().emit(1);
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(seen, equals([1]));

    await deps.dispose();
  });

  testWidgets('buildWhen and listenWhen are evaluated independently',
      (tester) async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_) => Counter(0)))
      ..ensureResolved([Counter]);

    final seen = <int>[];
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: BlocConsumer<Counter, int>(
            buildWhen: (previous, current) => current.isEven,
            listenWhen: (previous, current) => current.isOdd,
            listener: (context, state) => seen.add(state),
            builder: (context, state) {
              builds++;
              return Text('$state');
            },
          ),
        ),
      ),
    );

    expect(builds, equals(1));

    deps.get<Counter>().emit(1);
    await tester.pumpAndSettle();

    // Odd - listener runs, builder does not rebuild.
    expect(seen, equals([1]));
    expect(builds, equals(1));
    expect(find.text('0'), findsOneWidget);

    deps.get<Counter>().emit(2);
    await tester.pumpAndSettle();

    // Even - builder rebuilds, listener does not run.
    expect(seen, equals([1]));
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
    final seen = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: BlocConsumer<Counter, int>(
            bloc: explicitCounter,
            listener: (context, state) => seen.add(state),
            builder: (context, state) => Text('$state'),
          ),
        ),
      ),
    );

    expect(find.text('100'), findsOneWidget);

    explicitCounter.emit(101);
    await tester.pumpAndSettle();

    expect(find.text('101'), findsOneWidget);
    expect(seen, equals([101]));

    await deps.dispose();
    await explicitCounter.close();
  });
}
