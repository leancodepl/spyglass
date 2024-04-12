/// This example shows how `create` can return value after a delay.
library;

import 'package:spyglass/spyglass.dart';

Future<void> main() async {
  final sw = Stopwatch()..start();

  deps.addMany([
    Dependency<ServiceA>(
      create: (deps) async {
        final service = ServiceA();
        await service.init();
        return service;
      },
    ),
    Dependency<ServiceB>(
      create: (deps) async {
        final service = ServiceB();
        await service.init();
        return service;
      },
    ),
    Dependency<ServiceC>(
      create: (deps) async {
        final service = ServiceC();
        await service.init();
        return service;
      },
    ),
  ]);

  // Notice we don't trigger the initialization of ServiceC even though
  // it is registered and initializes in 2 seconds, while ServiceB takes
  // more time -- 3 seconds.
  await deps.ensureResolved([ServiceA, ServiceB]);

  sw.stop();
  print('Entire process took ${sw.elapsedMilliseconds}ms');
}

class ServiceA {
  Future<void> init() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    print('Service A initialized');
  }
}

class ServiceB {
  Future<void> init() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    print('Service B initialized');
  }
}

class ServiceC {
  Future<void> init() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    print('Service C initialized');
  }
}
