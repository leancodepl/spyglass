import 'package:flutter/foundation.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';
import 'package:flutter_test/flutter_test.dart';

class TrackedNotifier extends ChangeNotifier {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  test(
      'ChangeNotifierDependency calls dispose() automatically when '
      'removed', () async {
    final deps = Deps.detached()
      ..add(ChangeNotifierDependency<TrackedNotifier>(
          (_, __) => TrackedNotifier()));

    final notifier = deps.get<TrackedNotifier>();
    expect(notifier.disposed, isFalse);

    deps.remove<TrackedNotifier>();
    await Future<void>.delayed(Duration.zero);

    expect(notifier.disposed, isTrue);
  });

  test("an explicit dispose overrides ChangeNotifierDependency's default",
      () async {
    var customDisposeCalls = 0;
    Deps.detached()
      ..add(
        ChangeNotifierDependency<TrackedNotifier>(
          (_, __) => TrackedNotifier(),
          dispose: (notifier) {
            customDisposeCalls++;
            notifier.dispose();
          },
        ),
      )
      ..get<TrackedNotifier>()
      ..remove<TrackedNotifier>();

    await Future<void>.delayed(Duration.zero);

    expect(customDisposeCalls, equals(1));
  });

  test(
      'ListenableDependency (not ChangeNotifierDependency) has no default '
      'dispose - not every Listenable is disposable', () async {
    var disposeCalls = 0;
    final deps = Deps.detached()
      ..add(
        ListenableDependency<TrackedNotifier>(
          (_, __) => TrackedNotifier(),
          dispose: (notifier) => disposeCalls++,
        ),
      );

    final notifier = deps.get<TrackedNotifier>();
    deps.remove<TrackedNotifier>();
    await Future<void>.delayed(Duration.zero);

    // dispose only ran because we passed one explicitly - nothing in
    // ListenableDependency itself calls TrackedNotifier.dispose() here.
    expect(disposeCalls, equals(1));
    expect(notifier.disposed, isFalse);
  });
}
