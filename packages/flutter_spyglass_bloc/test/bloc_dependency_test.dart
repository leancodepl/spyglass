import 'package:bloc/bloc.dart';
import 'package:flutter_spyglass_bloc/flutter_spyglass_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class Counter extends Cubit<int> {
  Counter(super.initialState);
}

void main() {
  test(
      'the bloc/cubit is closed automatically when removed, via '
      'BlocBase.close()', () async {
    final deps = Deps.detached()
      ..add(BlocDependency<Counter>((_, __) => Counter(0)));

    final counter = deps.get<Counter>();
    expect(counter.isClosed, isFalse);

    deps.remove<Counter>();
    await Future<void>.delayed(Duration.zero);

    expect(counter.isClosed, isTrue);
  });

  test('an explicit dispose overrides the default close()', () async {
    var customDisposeCalls = 0;
    final deps = Deps.detached()
      ..add(
        BlocDependency<Counter>(
          (_, __) => Counter(0),
          dispose: (counter) {
            customDisposeCalls++;
            return counter.close();
          },
        ),
      );

    final counter = deps.get<Counter>();
    deps.remove<Counter>();
    await Future<void>.delayed(Duration.zero);

    expect(customDisposeCalls, equals(1));
    expect(counter.isClosed, isTrue);
  });
}
