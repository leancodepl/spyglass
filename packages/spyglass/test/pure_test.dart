import 'package:spyglass/spyglass.dart';
import 'package:test/test.dart';

void main() {
  test('pure', () async {
    globalDeps.register(
      Dependency(
        create: (deps) async {
          final value = await deps.getLater<int>();
          return value > 10;
        },
      ),
    );

    Future<void>.delayed(const Duration(seconds: 3), () {
      globalDeps.register(Dependency<int>(create: (_) => 5));
    });

    expect(globalDeps.getLater<bool>(), completion(isFalse));
  });
}
