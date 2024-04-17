# Spyglass [WIP]

> Note: This package is in active development and its API might change
> frequently. Currently it's basically functional but might contain frequent
> bugs. It has not yet been thoroughly tested and is missing documentation and
> examples.

Reliable service locator for all your Dart needs.

## Installation & usage

Add the latest `spyglass` to your pubspec and you're ready to go!

```sh
dart pub add spyglass
```

A basic hello world:

```dart
import 'package:spyglass/spyglass.dart';

void main() {
  deps.add(Dependency.value(Greeter()));

  final greeter = deps.get<Greeter>();

  greeter.greet();
}

class Greeter {
  void greet() {
    print('Hello world!');
  }
}
```

Register dependencies:

```dart
// simplest way
deps.add(Dependency.value(SomeService()));

// lazy
deps.add(Dependency(create: (deps) => SomeService()));

// with dispose function
deps.add(
  Dependency(
    create: (deps) => SomeService(),
    dispose: (service) => service.dispose(),
  ),
);

// with another dependency as parameter
deps.add(
  Dependency(
    create: (deps) => SomeService(
      other: deps.get<SomeOtherService>(),
    ),
  ),
);

// live updates on change
deps.add(
  Dependency(
    create: (deps) => SomeService(
      other: deps.get<SomeOtherService>(),
    ),
    when: (deps) => deps.watch<SomeOtherService>(),
    update: (deps, service) {
      return service..other = deps.get<SomeOtherService>();
    },
  ),
);

// async initialization
deps.add(
  Dependency(
    create: (deps) async {
      final service = SomeService();
      await service.ensureInitialized();
      return service;
    },
  ),
);

// await other dependencies
deps.add(
  Dependency(
    create: (deps) async {
      final other = deps.getAsync<SomeOtherService>();
      return SomeService(
        other: other,
      );
    },
  ),
);
```

Read & watch changes:

```dart
// sync
SomeService service = deps.get<SomeService>();

// optional
SomeService? service = deps.tryGet<SomeService>();

// asynchronously initialized
SomeService service = await deps.getAsync<SomeService>();

// watch updates
Stream<SomeService> serviceStream = deps.watch<SomeService>();
```
