# Spyglass [WIP]

> Note: This package is in active development and its API might change
> frequently. Currently it's basically functional but might contain frequent
> bugs. It has not yet been thoroughly tested and is missing documentation and
> examples.

Reliable service locator for all your Dart needs.

## Installation

```sh
dart pub add spyglass
```

## Quick start

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

`deps` is the global, ambient `Deps` container - a box you register services
into and look them up from anywhere, by type. Everything below builds on
that one idea: `deps.add(...)` to register, `deps.get<T>()` to look up.

> **A note on `create`:** every `Dependency`'s `create` callback takes two
> positional parameters - `(DepsReader deps, T? oldValue)`. `oldValue` is
> only relevant for the "computed dependency" recipe below; for a plain
> one-shot factory, just ignore it (`(deps, _) => ...`).

## Common recipes

### Registering a dependency

```dart
// A value that already exists and never changes.
deps.add(Dependency.value(SomeService()));

// Lazily created on first use.
deps.add(Dependency((deps, _) => SomeService()));

// With cleanup when removed/replaced/the scope is disposed.
deps.add(
  Dependency(
    (deps, _) => SomeService(),
    dispose: (service) => service.dispose(),
  ),
);

// Depending on another registered service.
deps.add(
  Dependency(
    (deps, _) => SomeService(other: deps.get<SomeOtherService>()),
  ),
);
```

### Reading a dependency

```dart
// Throws DependencyNotRegisteredException/DependencyNotResolvedException
// if it isn't registered/hasn't finished being created.
SomeService service = deps.get<SomeService>();

// Same, but returns null instead of throwing in either case.
SomeService? service = deps.tryGet<SomeService>();

// Returns the current value without ever triggering creation - null if
// it's registered but hasn't been resolved yet (or isn't registered).
SomeService? service = deps.peek<SomeService>();
```

### Watching for changes

```dart
// Fires whenever a *new instance* is registered under this type (add()
// with a changed cacheKey, or replace()) - not on that instance's own
// internal state changes. Cheap: never subscribes to the value itself.
Stream<SomeService> instances = deps.watchInstance<SomeService>();

// Fires on registration changes AND on internal state changes reported by
// the resolved value's DependencyObserver, if it has one - see "Observing
// internal state changes" below.
Stream<SomeService> full = deps.watch<SomeService>();

// Combine several dependencies - handy for a widget/effect that needs more
// than one. watch2..watch5 cover 2-5 types; they use watchInstance
// semantics, not watch, for each.
deps.watch2<UserService, SettingsService>().listen((values) {
  final (user, settings) = values;
  // ...
});
```

### Computed dependencies

A dependency can recompute its value in reaction to another one changing -
`create` is simply called again, with the previous value as `oldValue`,
whenever a key it read via `deps.watchInstance(...)` (not the untracked
`deps.get(...)`) on its *last* run gets re-registered under a new instance.
There's no separate list of "what to observe" to keep in sync - reading via
`watchInstance` inside `create` *is* the declaration, rediscovered fresh on
every run:

```dart
deps.add(
  Dependency<UserGreeting>((deps, oldValue) {
    final user = deps.watchInstance<UserService>().currentUser;
    return oldValue == null
        ? UserGreeting('Hello, ${user.name}!')
        : oldValue.copyWith(text: 'Hello, ${user.name}!');
  }),
);
```

Which keys are tracked can even depend on `oldValue`, so a `create` that
takes a different branch on a later run automatically re-subscribes to
whatever it read *this* time, dropping keys it no longer reads.

The initial value is available synchronously, right after `add()`. A
*reactive* re-run, triggered by a later `replace()`/`add()` elsewhere,
happens asynchronously - `deps.get<UserGreeting>()` immediately after
`replace()` can still see the old value for a moment. Prefer
`deps.watch<UserGreeting>()` over polling `get()` when you need to react to
the update as soon as it lands.

### Registering the same instance under another type

Useful for exposing a concrete implementation through an interface, so
either can be looked up:

```dart
deps.addAll([
  Dependency<SomeServiceImpl>((deps, _) => SomeServiceImpl()),
  const Alias<SomeService, SomeServiceImpl>(),
]);

deps.get<SomeService>() == deps.get<SomeServiceImpl>(); // true
```

The alias is lazy, stays in sync with a later `deps.replace<SomeServiceImpl>(...)`,
and never disposes anything itself - only `SomeServiceImpl`'s own `dispose`
(if any) tears the shared instance down. `deps.watch<SomeService>()` does
*not* react to the shared instance's internal state changes by default -
`SomeService` declares nothing about being observable, so nothing is
assumed; pass `createObserver` to `Alias` explicitly if you want that.

One caveat worth knowing: because this is sugar for a second, independent
registration, removing only `SomeServiceImpl` (bare
`deps.remove<SomeServiceImpl>()`) leaves the `SomeService` key registered
and pointing at what's now a disposed instance. Register and remove them
together - e.g. via a `Module` (see below), or by removing both keys
explicitly.

### Observing internal state changes

Beyond "a new instance was registered," a dependency can report its own
internal state changes (e.g. a mutable object notifying its listeners) so
`deps.watch<T>()` reacts to those too, not just registration:

```dart
deps.add(
  Dependency<Counter>(
    (deps, _) => Counter(),
    createObserver: (counter) => CounterObserver(counter),
  ),
);

deps.watch<Counter>().listen((counter) => print('now: ${counter.value}'));

class CounterObserver extends DependencyObserver<Counter> {
  CounterObserver(this.counter) {
    counter.addListener(_onChange);
  }

  final Counter counter;

  void _onChange() => notifyStateChanged();

  @override
  Future<void> dispose() async => counter.removeListener(_onChange);
}
```

One observer is created per resolved value (shared by every subscriber),
and only once something actually calls `watch()` - a dependency that's
only ever plain-read via `get()` never pays for this. If you're on Flutter,
[`flutter_spyglass`](https://pub.dev/packages/flutter_spyglass) ships
`ChangeNotifierDependency`/`ListenableDependency` for `ChangeNotifier`
/`Listenable` values, and
[`flutter_spyglass_bloc`](https://pub.dev/packages/flutter_spyglass_bloc)
ships `BlocDependency` for `bloc`/`cubit` - you rarely need to write a
`DependencyObserver` by hand outside plain Dart code.

### Scoping

`Deps` instances form a tree: a child scope (`fork`) inherits everything
its ancestors have registered, and can override specific keys locally
without touching the parent. Changes in an ancestor (a new registration, a
replacement, an internal state change) propagate down to every descendant
that hasn't shadowed that key itself.

```dart
final authScope = deps.fork(debugLabel: 'AuthScope');
authScope.add(Dependency<AuthToken>.value(AuthToken('...')));

authScope.get<AuthToken>();       // registered directly in authScope
authScope.get<SomeGlobalService>(); // inherited from deps (the parent)

await authScope.dispose(); // disposes only what authScope itself registered
```

`Deps.detached()` creates a scope with no parent at all - useful for tests,
so each test gets a clean, isolated container instead of sharing the
global `deps`/`Deps.root`. `Deps.runZoned` lets you run code with a
specific `Deps` as the ambient `deps`/`globalDeps` for that zone, without
needing to thread it through every call explicitly.

### Grouping dependencies

A `Module` bundles several dependencies so they're added and removed
together as one unit:

```dart
final authModule = Module([
  Dependency<AuthService>((deps, _) => AuthService()),
  Dependency<TokenStorage>((deps, _) => TokenStorage()),
], debugLabel: 'Auth');

deps.add(authModule);
// ...
deps.remove(authModule); // removes both AuthService and TokenStorage
```

`deps.remove(...)` also accepts a fresh `Module`/`Dependency` describing
the same types - lookup is by type, not by holding onto the exact instance
that was originally registered.

### Startup dependencies via tags

Tag dependencies that need to be ready before the rest of the app starts,
then force them all to resolve up front:

```dart
deps.add(Dependency<Database>((deps, _) => Database(), tags: const ['startup']));
deps.add(Dependency<Analytics>((deps, _) => Analytics(), tags: const ['startup']));

void main() {
  final startupKeys = deps.getEntriesWithTag('startup').map((d) => d.key);
  deps.ensureResolved(startupKeys); // synchronous - forces creation now

  runApp(MyApp());
}
```

### Removing and replacing

```dart
final unregister = deps.add(Dependency<Foo>((deps, _) => Foo()));
unregister(); // equivalent to deps.remove<Foo>()

// add() again under the same key/cacheKey is a no-op - the existing value
// is left in place. replace() always tears down and recreates.
deps.replace(Dependency<Foo>((deps, _) => Foo()));
```

### Error handling

| Exception                            | Thrown by                    | When                                                          |
| ------------------------------------- | ----------------------------- | -------------------------------------------------------------- |
| `DependencyNotRegisteredException`    | `get`                         | Nothing is registered under that key in this scope or its ancestors. |
| `DependencyNotResolvedException`      | `get`                         | It's registered, but `create` hasn't finished producing a value yet. |
| `DepsDisposedException`                | `add`, `get`, `tryGet`        | The scope has already been disposed.                          |
| `DependencyCycleException`             | `get` (during creation)       | `create` re-enters resolving its own key before finishing.    |

`isRegistered<T>()` and `tryGet<T>()` are the non-throwing ways to check
before you `get`.

## See also

- [`flutter_spyglass`](https://pub.dev/packages/flutter_spyglass) - Flutter
  integration: a `DepsProvider` widget, `context.get`/`watch`/`watchInstance`
  /`select`, and Flutter-flavored `Dependency` subclasses. Its README also
  has [benchmark results against `provider`](https://github.com/leancodepl/spyglass/tree/main/packages/flutter_spyglass#benchmarks).
- [`flutter_spyglass_bloc`](https://pub.dev/packages/flutter_spyglass_bloc) -
  `bloc`/`cubit` integration on top of `flutter_spyglass`.
