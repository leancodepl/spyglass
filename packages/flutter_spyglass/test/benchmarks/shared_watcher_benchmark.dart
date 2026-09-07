import 'package:flutter/material.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'bench_stats.dart';
import 'services.dart';

/// The mirror image of the other benchmarks: instead of [serviceCount]
/// distinct services with one watcher each, this registers a single
/// service and mounts many widgets that all watch it.
///
/// None of the other benchmarks exercise this shape - they all use distinct
/// types with one watcher each, which never had more than one subscription
/// per type even before `_DepsElement` consolidated its subscriptions (see
/// deps_provider.dart). This is the scenario that consolidation actually
/// targets: many widgets sharing one dependency, which is the common case
/// for something like a shared AuthService or ThemeService.
///
/// Run with: flutter test test/benchmarks/shared_watcher_benchmark.dart
void main() {
  const warmUp = 3;
  const runs = 10;
  const watcherCount = 100;

  testWidgets('Shared watcher: $watcherCount widgets watching 1 service',
      (tester) async {
    Deps? currentDeps;

    // --- Build: watcherCount widgets mounting against 1 registered service.
    final spyglassBuildStats = await runBenchmark(
      warmUpRuns: warmUp,
      measuredRuns: runs,
      setUp: () async {
        await tester.pumpWidget(const SizedBox());
        await currentDeps?.dispose();
        currentDeps = null;
      },
      body: () async {
        final scopeDeps = Deps.root.fork()
          ..add(spyglassFactories[0](0))
          ..ensureResolved([Svc0]);
        currentDeps = scopeDeps;

        await tester.pumpWidget(
          MaterialApp(
            home: DepsProvider(
              deps: scopeDeps,
              introduceScope: false,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < watcherCount; i++)
                      Builder(builder: spyglassReaders[0]),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    final providerBuildStats = await runBenchmark(
      warmUpRuns: warmUp,
      measuredRuns: runs,
      setUp: () async {
        await tester.pumpWidget(const SizedBox());
      },
      body: () async {
        await tester.pumpWidget(
          MaterialApp(
            home: MultiProvider(
              providers: [providerFactories[0](0)],
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < watcherCount; i++)
                      Builder(builder: providerReaders[0]),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    await currentDeps?.dispose();

    printComparison(
      'Shared watcher build ($watcherCount widgets, 1 service)',
      {'spyglass': spyglassBuildStats, 'provider': providerBuildStats},
    );

    // --- Rebuild: mount once, then repeatedly mutate the shared service.
    var nextValue = 1000;

    final scopeDeps = Deps.root.fork()
      ..add(spyglassFactories[0](0))
      ..ensureResolved([Svc0]);

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: scopeDeps,
          introduceScope: false,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < watcherCount; i++)
                  Builder(builder: spyglassReaders[0]),
              ],
            ),
          ),
        ),
      ),
    );

    final spyglassRebuildStats = await runBenchmark(
      warmUpRuns: warmUp,
      measuredRuns: runs,
      setUp: () async => resetBuildCounts(),
      body: () async {
        spyglassGetters[0](scopeDeps).update(nextValue++);
        await tester.pump();
      },
    );
    _expectAllWatchersRebuiltOnce('spyglass', watcherCount);

    await tester.pumpWidget(const SizedBox());
    await scopeDeps.dispose();

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [providerFactories[0](0)],
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < watcherCount; i++)
                  Builder(builder: providerReaders[0]),
              ],
            ),
          ),
        ),
      ),
    );
    final providerContext = tester.element(find.byType(SingleChildScrollView));

    final providerRebuildStats = await runBenchmark(
      warmUpRuns: warmUp,
      measuredRuns: runs,
      setUp: () async => resetBuildCounts(),
      body: () async {
        providerGetters[0](providerContext).update(nextValue++);
        await tester.pump();
      },
    );
    _expectAllWatchersRebuiltOnce('provider', watcherCount);

    await tester.pumpWidget(const SizedBox());

    printComparison(
      'Shared watcher rebuild ($watcherCount widgets, 1 service changes)',
      {'spyglass': spyglassRebuildStats, 'provider': providerRebuildStats},
    );

    // --- Dispose: mount fresh each iteration, then unmount + teardown.
    final spyglassDisposeStats = await runBenchmark(
      warmUpRuns: warmUp,
      measuredRuns: runs,
      setUp: () async {
        final d = Deps.root.fork()
          ..add(spyglassFactories[0](0))
          ..ensureResolved([Svc0]);
        currentDeps = d;

        await tester.pumpWidget(
          MaterialApp(
            home: DepsProvider(
              deps: d,
              introduceScope: false,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < watcherCount; i++)
                      Builder(builder: spyglassReaders[0]),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      body: () async {
        await tester.pumpWidget(const SizedBox());
        await currentDeps!.dispose();
        await tester.pump();
        await tester.pump();
      },
    );

    final providerDisposeStats = await runBenchmark(
      warmUpRuns: warmUp,
      measuredRuns: runs,
      setUp: () async {
        await tester.pumpWidget(
          MaterialApp(
            home: MultiProvider(
              providers: [providerFactories[0](0)],
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < watcherCount; i++)
                      Builder(builder: providerReaders[0]),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      body: () async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.pump();
      },
    );

    printComparison(
      'Shared watcher dispose ($watcherCount widgets, 1 service)',
      {'spyglass': spyglassDisposeStats, 'provider': providerDisposeStats},
    );
  });
}

void _expectAllWatchersRebuiltOnce(String label, int watcherCount) {
  if (buildCounts[0] != watcherCount) {
    fail(
      '$label: expected all $watcherCount watchers to rebuild once after '
      'the shared service changed, but buildCounts[0] was ${buildCounts[0]}.',
    );
  }
}
