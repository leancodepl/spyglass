import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spyglass/spyglass.dart';

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

class MyService {
  MyService(this.string);

  final String string;

  Future<void> ensureInitialized() async {
    await Future<void>.delayed(const Duration(seconds: 3));
  }

  void echo() {
    debugPrint(string);
  }
}

class MyDependentService {
  MyDependentService(this.service);

  final MyService service;

  void echo() {
    debugPrint('echo from dependent');
    service.echo();
  }
}
