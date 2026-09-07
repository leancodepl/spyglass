import 'package:flutter/material.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'bench_stats.dart';
import 'services.dart';

/// Mounts a subtree with [serviceCount] mutable services, each observed by
/// exactly one leaf, then mutates ALL of them before a single pump - the
/// worst case for any implementation that delivers a "this service changed"
/// notification to more than just that service's own watcher(s).
///
/// This is the scenario that caught a real regression during development:
/// routing internal state changes through one shared event stream that every
/// subscriber filters individually (instead of routing them straight to the
/// dependency's own watcher(s)) turned "1 of 100 services changes" and
/// "100 of 100 services change" into wildly different cost-per-notification,
/// because every notification had to be checked against every subscriber in
/// the scope - not just the one(s) that cared about it.
///
/// Run with: flutter test test/benchmarks/fanout_benchmark.dart
void main() {
  const warmUp = 3;
  const runs = 10;

  testWidgets('Fan-out: all $serviceCount services change at once',
      (tester) async {
    var nextValue = 1000;

    // --- spyglass: mount once, then repeatedly mutate all + pump.
    final scopeDeps = Deps.root.fork()
      ..addAll([
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
        for (var i = 0; i < serviceCount; i++) {
          spyglassGetters[i](scopeDeps).update(nextValue++);
        }
        await tester.pump();
      },
    );
    _expectEveryLeafRebuiltOnce('spyglass');

    await tester.pumpWidget(const SizedBox());
    await scopeDeps.dispose();

    // --- provider: mount once, then repeatedly mutate all + pump.
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
        for (var i = 0; i < serviceCount; i++) {
          providerGetters[i](providerContext).update(nextValue++);
        }
        await tester.pump();
      },
    );
    _expectEveryLeafRebuiltOnce('provider');

    await tester.pumpWidget(const SizedBox());

    printComparison(
      'Fan-out (all $serviceCount services change)',
      {'spyglass': spyglassStats, 'provider': providerStats},
    );
  });
}

void _expectEveryLeafRebuiltOnce(String label) {
  for (var i = 0; i < serviceCount; i++) {
    if (buildCounts[i] != 1) {
      fail(
        '$label: expected leaf $i to rebuild exactly once after every '
        'service changed, but it rebuilt ${buildCounts[i]} time(s).',
      );
    }
  }
}
