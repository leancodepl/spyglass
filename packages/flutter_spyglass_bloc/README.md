`bloc`/`cubit` integration for [flutter_spyglass](https://pub.dev/packages/flutter_spyglass).

## Features

* `BlocDependency<TBloc>` - register a `Bloc`/`Cubit` as a spyglass dependency; it's disposed
  (via `close()`) automatically and any widget using `context.watch<TBloc>()` rebuilds on every
  emitted state.
* `BlocBuilder<TBloc, TState>` - the flutter_spyglass counterpart to flutter_bloc's `BlocBuilder`.
  Rebuilds with the bloc's state directly, optionally filtered with `buildWhen`.
* `BlocListener<TBloc, TState>` - the counterpart to `BlocListener`. Invokes a `listener` for
  side effects (navigation, showing a `SnackBar`, ...) on every state, without rebuilding,
  optionally filtered with `listenWhen`.
* `BlocConsumer<TBloc, TState>` - the counterpart to `BlocConsumer`. Combines `BlocBuilder` and
  `BlocListener` for a state change that needs both a rebuild and a side effect.

## Usage

```dart
DepsProvider(
  register: [
    BlocDependency<CounterCubit>((_) => CounterCubit()),
  ],
  child: BlocBuilder<CounterCubit, int>(
    builder: (context, count) => Text('$count'),
  ),
);
```

Pass `buildWhen` to control when the builder is invoked, just like flutter_bloc's `BlocBuilder`:

```dart
BlocBuilder<CounterCubit, int>(
  buildWhen: (previous, current) => current.isEven,
  builder: (context, count) => Text('$count'),
);
```

An explicit `bloc` can be supplied instead of resolving one from the nearest `Deps` scope:

```dart
BlocBuilder<CounterCubit, int>(
  bloc: myCounterCubit,
  builder: (context, count) => Text('$count'),
);
```

`BlocListener` runs side effects in response to state changes, without rebuilding anything itself:

```dart
BlocListener<CounterCubit, int>(
  listenWhen: (previous, current) => current == 10,
  listener: (context, count) => showDialog(
    context: context,
    builder: (_) => const AlertDialog(title: Text('You reached 10!')),
  ),
  child: const CounterView(),
);
```

`BlocConsumer` combines both when a single state change needs a rebuild and a side effect:

```dart
BlocConsumer<CounterCubit, int>(
  listener: (context, count) {
    if (count == 10) ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Reached 10!')));
  },
  builder: (context, count) => Text('$count'),
);
```
