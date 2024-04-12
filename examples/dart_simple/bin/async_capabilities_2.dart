/// This example shows how `create` can return value after a delay.
library;

import 'package:spyglass/spyglass.dart';

Future<void> main() async {
  final sw = Stopwatch()..start();

  deps.addMany([
    Dependency<UsernameProvider>(
      create: (deps) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        return UsernameProvider();
      },
    ),
    Dependency<Greeter>(
      create: (deps) async {
        final usernameProvider = await deps.getAsync<UsernameProvider>();
        final username = await usernameProvider.getUsername();
        return Greeter(name: username);
      },
    ),
  ]);

  // Wait for Greeter to be available
  final greeter = await deps.getAsync<Greeter>();

  greeter.greet();

  sw.stop();
  print('Entire process took ${sw.elapsedMilliseconds}ms');
}

class UsernameProvider {
  Future<String> getUsername() => Future.delayed(
        const Duration(seconds: 1),
        () => 'John Doe',
      );
}

class Greeter {
  Greeter({required this.name});

  final String name;

  void greet() {
    print('Hello $name!');
  }
}
