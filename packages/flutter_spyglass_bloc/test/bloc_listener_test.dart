import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spyglass_bloc/flutter_spyglass_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class Counter extends Cubit<int> {
  Counter(super.initialState);
}

void main() {
  testWidgets(
      'invokes listener for every emission by default, without '
      'rebuilding the child', (tester) async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_, __) => Counter(0)))
      ..ensureResolved([Counter]);

    var childBuilds = 0;
    final seen = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: BlocListener<Counter, int>(
            listener: (context, state) => seen.add(state),
            child: Builder(builder: (context) {
              childBuilds++;
              return const SizedBox();
            }),
          ),
        ),
      ),
    );

    expect(childBuilds, equals(1));
    expect(seen, isEmpty);

    deps.get<Counter>().emit(1);
    await tester.pumpAndSettle();

    expect(seen, equals([1]));
    expect(childBuilds, equals(1));

    await deps.dispose();
  });

  testWidgets('listenWhen controls whether an emission triggers listener',
      (tester) async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_, __) => Counter(0)))
      ..ensureResolved([Counter]);

    final seen = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: BlocListener<Counter, int>(
            listenWhen: (previous, current) => current.isEven,
            listener: (context, state) => seen.add(state),
            child: const SizedBox(),
          ),
        ),
      ),
    );

    deps.get<Counter>().emit(1);
    await tester.pumpAndSettle();
    expect(seen, isEmpty);

    deps.get<Counter>().emit(2);
    await tester.pumpAndSettle();
    expect(seen, equals([2]));

    await deps.dispose();
  });

  testWidgets('an explicit bloc is used instead of the one from Deps',
      (tester) async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_, __) => Counter(0)))
      ..ensureResolved([Counter]);
    final explicitCounter = Counter(100);
    final seen = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: deps,
          introduceScope: false,
          child: BlocListener<Counter, int>(
            bloc: explicitCounter,
            listener: (context, state) => seen.add(state),
            child: const SizedBox(),
          ),
        ),
      ),
    );

    explicitCounter.emit(101);
    await tester.pumpAndSettle();

    expect(seen, equals([101]));

    await deps.dispose();
    await explicitCounter.close();
  });
}
