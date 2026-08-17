import 'package:flutter/material.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'bench_stats.dart';
import 'services.dart';

/// Mounts a subtree with [serviceCount] mutable services, each observed by
/// exactly one leaf, then mutates a single service and measures the cost of
/// the resulting frame. Both libraries update in place (ChangeNotifier-style)
/// rather than by re-describing the widget tree from above, which is how
/// this kind of update is idiomatically done with either library - no
/// pumpWidget-with-a-new-tree call is involved in the timed portion.
///
/// Also asserts that only the leaf observing the mutated service rebuilds,
/// which is the whole point of fine-grained dependency observation.
///
/// Run with: flutter test test/benchmarks/rebuild_benchmark.dart
void main() {
  const warmUp = 3;
  const runs = 10;
  const targetIndex = 42;

  testWidgets('Selective rebuild: 1 of $serviceCount services changes',
      (tester) async {
    var nextValue = 1000;

    // --- spyglass: mount once, then repeatedly mutate + pump.
    final scopeDeps = Deps.root.fork()
      ..addMany([
        for (var i = 0; i < serviceCount; i++) spyglassFactories[i](i),
      ])
      ..ensureResolved(serviceTypes);

    await tester.pumpWidget(
      MaterialApp(
        home: DepsProvider(
          deps: scopeDeps,
          introduceScope: false,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < serviceCount; i++)
                  Builder(builder: spyglassReaders[i]),
              ],
            ),
          ),
        ),
      ),
    );

    final spyglassStats = await runBenchmark(
      warmUpRuns: warmUp,
      measuredRuns: runs,
      setUp: () async => resetBuildCounts(),
      body: () async {
        spyglassGetters[targetIndex](scopeDeps).update(nextValue++);
        await tester.pump();
      },
    );
    _expectIsolatedRebuild('spyglass', targetIndex);

    await tester.pumpWidget(const SizedBox());
    await scopeDeps.dispose();

    // --- provider: mount once, then repeatedly mutate + pump.
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            for (var i = 0; i < serviceCount; i++) providerFactories[i](i),
          ],
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < serviceCount; i++)
                  Builder(builder: providerReaders[i]),
              ],
            ),
          ),
        ),
      ),
    );
    final providerContext = tester.element(find.byType(SingleChildScrollView));

    final providerStats = await runBenchmark(
      warmUpRuns: warmUp,
      measuredRuns: runs,
      setUp: () async => resetBuildCounts(),
      body: () async {
        providerGetters[targetIndex](providerContext).update(nextValue++);
        await tester.pump();
      },
    );
    _expectIsolatedRebuild('provider', targetIndex);

    await tester.pumpWidget(const SizedBox());

    printComparison(
      'Selective rebuild ($serviceCount services, 1 changes)',
      {'spyglass': spyglassStats, 'provider': providerStats},
    );
  });
}

void _expectIsolatedRebuild(String label, int targetIndex) {
  for (var i = 0; i < serviceCount; i++) {
    final expected = i == targetIndex ? 1 : 0;
    if (buildCounts[i] != expected) {
      fail(
        '$label: expected leaf $i to rebuild $expected time(s) after the '
        'last change, but it rebuilt ${buildCounts[i]} time(s). Rebuild '
        'isolation is broken for this run.',
      );
    }
  }
}
