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
      (deps, _) => Greeter(),
      dispose: (greeter) => greeter.dispose(),
    ),
  ],
  builder: (context, child) => Center(
    child: Text(context.watch<Greeter>().message),
  ),
);
```

For more advanced usage of the `Deps` container/scope see docs for `spyglass`.

## Benchmarks

`test/benchmarks/` compares `flutter_spyglass` against `provider` on
equivalent widget-tree scenarios, using `benchmark_harness`-style
warm-up-then-measure runs (3 warm-up + 10 measured, per benchmark) driven
through `flutter_test`'s widget tester. Run them yourself with:

```sh
flutter test test/benchmarks/<name>_benchmark.dart
```

| Benchmark | What it measures |
| --- | --- |
| `initial_build` | First build of a subtree with 100 independently-retrievable, eagerly-resolved services, one watcher each. |
| `rebuild` | Mutating 1 of 100 watched services in place and measuring the resulting frame - and asserting only that one watcher's leaf rebuilds. |
| `fanout` | The worst case for rebuild: mutating all 100 watched services before a single pump, to catch notification-delivery costs that scale with subscriber count instead of just the one(s) that actually changed. |
| `shared_watcher` | The mirror image of the others: one service, 100 widgets all watching it - the common "shared `AuthService`/`ThemeService`" shape - covering build, rebuild, and dispose. |
| `unwatched` | The same shapes as `initial_build`/`dispose`, but every leaf does a plain, non-reactive read (`get`, not `watch`) - the pure service-locator usage pattern, where no `DependencyObserver`/stream machinery should ever be built. |
| `dispose` | Unmounting a subtree of 100 eagerly-created, watched services and measuring teardown - N `InheritedElement` subscriptions removed plus N `ChangeNotifier`s disposed. |

A representative run on a single dev machine, in `flutter test`'s debug
mode (median of 10 runs, milliseconds):

| Benchmark | spyglass | provider |
| --- | --- | --- |
| Initial build (100 services) | 37.65 | 47.94 |
| Selective rebuild (1 of 100 changes) | 8.50 | 5.28 |
| Fan-out (all 100 change) | 42.47 | 31.78 |
| Shared watcher: build (100 widgets, 1 service) | 47.12 | 28.96 |
| Shared watcher: rebuild | 14.32 | 29.58 |
| Shared watcher: dispose | 11.04 | 14.46 |
| Unwatched: initial build | 34.77 | 17.10 |
| Unwatched: dispose | 9.57 | 8.57 |
| Unwatched: re-register (add/replace, not watched) | 3.65 | 29.54 |
| Dispose (100 services, watched) | 59.15 | 10.74 |

**Take these numbers as illustrative, not authoritative** - they're a
single run of a debug-mode `flutter test` on one machine, and re-running
the same benchmark minutes apart on the same machine showed 2-3x swings
for some scenarios (dispose-heavy ones especially - background CPU/GC
load matters a lot here). Re-run locally for numbers that reflect your
own machine and Flutter version. What did hold up consistently across
repeated runs:

- Initial build, selective rebuild, and fan-out are roughly on par with
  `provider` either way - close enough that which one comes out ahead in
  a given run is mostly noise.
- Registering/replacing unwatched dependencies is consistently and
  substantially faster in spyglass - `ManagedDependency` only builds its
  `DependencyObserver`/stream machinery lazily, on the first `watch()`.
- Building many widgets that all watch one shared dependency is
  consistently slower in spyglass than `provider`'s consolidated
  `InheritedWidget` dependency tracking - a candidate for future work.
- Bulk disposal (many watched services torn down at once) is consistently
  and substantially slower in spyglass than `provider` - the other clear
  candidate for future work.
