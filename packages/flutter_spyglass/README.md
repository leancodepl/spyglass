# Spyglass for Flutter [WIP]

> Note: This package is in active development and its API might change
> frequently. Currently it's basically functional but might contain frequent
> bugs. It has not yet been thoroughly tested and is missing documentation and
> examples.

Reliable service locator for all your Flutter needs.

## Installation & usage

Add the latest `flutter_spyglass` to your pubspec and you're ready to go!

```sh
flutter pub add flutter_spyglass
```

Basic usage:

```dart
// Wrap a widget in DepsProvider and read value from context.
// All dependencies in [DepsProvider.register] will be disposed of
// when DepsProvider is disposed
DepsProvider(
  register: [
    Dependency<Greeter>(
      create: (deps) => Greeter(),
      dispose: (greeter) => greeter.dispose(),
    ),
  ],
  builder: (context, child) => Center(
    child: Text(context.watch<Greeter>().message),
  ),
);
```

For more advanced usage of the `Deps` container/scope see docs for `spyglass`.
