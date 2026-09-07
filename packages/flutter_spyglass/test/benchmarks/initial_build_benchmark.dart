import 'package:flutter/material.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'bench_stats.dart';
import 'services.dart';

/// Registers [serviceCount] independently-retrievable dependencies, forces
/// them to eagerly resolve (matching provider's `lazy: false`), and does the
/// first build of a subtree with a leaf reading one of them.
///
/// Run with: flutter test test/benchmarks/initial_build_benchmark.dart
void main() {
  const warmUp = 3;
  const runs = 10;

  testWidgets('Initial build: $serviceCount services', (tester) async {
    Deps? currentDeps;

    final spyglassStats = await runBenchmark(
      warmUpRuns: warmUp,
      measuredRuns: runs,
      setUp: () async {
        await tester.pumpWidget(const SizedBox());
        await currentDeps?.dispose();
        currentDeps = null;
      },
      body: () async {
        final scopeDeps = Deps.root.fork()
          ..addAll([
            for (var i = 0; i < serviceCount; i++) spyglassFactories[i](i),
          ])
          ..ensureResolved(serviceTypes);
        currentDeps = scopeDeps;

        await tester.pumpWidget(
          MaterialApp(
            home: DepsProvider(
              deps: scopeDeps,
              introduceScope: false,
              child: Builder(builder: spyglassReaders[0]),
            ),
          ),
        );
      },
    );

    final providerStats = await runBenchmark(
      warmUpRuns: warmUp,
      measuredRuns: runs,
      setUp: () async {
        await tester.pumpWidget(const SizedBox());
      },
      body: () async {
        await tester.pumpWidget(
          MaterialApp(
            home: MultiProvider(
              providers: [
                for (var i = 0; i < serviceCount; i++) providerFactories[i](i),
              ],
              child: Builder(builder: providerReaders[0]),
            ),
          ),
        );
      },
    );

    await currentDeps?.dispose();

    printComparison('Initial build ($serviceCount services)', {
      'spyglass': spyglassStats,
      'provider': providerStats,
    });
  });
}
