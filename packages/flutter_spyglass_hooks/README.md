`flutter_hooks` integration for [flutter_spyglass](https://pub.dev/packages/flutter_spyglass).

## Features

* `useDeps()` - obtain the nearest `Deps` scope, the hook equivalent of `DepsProvider.of`/`context.deps`.
* `useDependency<T>()` - watch a dependency fully, the hook equivalent of `context.watch<T>()`.
* `useDependencyInstance<T>()` - watch a dependency's registration only, the hook equivalent of
  `context.watchInstance<T>()`.
* `useRegisterDeps()` - register dependencies on mount and unregister them on unmount, the hook
  form of `DepsProvider.register`.

## Usage

```dart
class Counter extends HookWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final counter = useDependency<CounterService>();
    return Text('${counter.value}');
  }
}
```

Registering a dependency for the lifetime of a hook widget:

```dart
class CounterScope extends HookWidget {
  const CounterScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    useRegisterDeps([
      Dependency<CounterService>((_) => CounterService()),
    ]);
    return child;
  }
}
```
