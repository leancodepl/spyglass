/// This example shows how `getAsync` can be used to wait for a dependency
/// that will be registered at some point in the future.
library;

import 'package:spyglass/spyglass.dart';

Future<void> main() async {
  final sw = Stopwatch()..start();

  deps.add(
    Dependency(
      create: (deps) async {
        // UsernameProvider hasn't been registered yet
        final usernameProvider = await deps.getAsync<UsernameProvider>();
        return Greeter(name: usernameProvider.getUsername());
      },
    ),
  );

  // Register UsernameProvider after a delay
  Future<void>.delayed(const Duration(seconds: 3), () {
    deps.add(Dependency.value(UsernameProvider()));
  });

  // Wait for Greeter to be available
  final greeter = await deps.getAsync<Greeter>();

  greeter.greet();

  sw.stop();
  print('Entire process took ${sw.elapsedMilliseconds}ms');
}

class UsernameProvider {
  String getUsername() {
    return 'John Doe';
  }
}

class Greeter {
  Greeter({required this.name});

  final String name;

  void greet() {
    print('Hello $name!');
  }
}
