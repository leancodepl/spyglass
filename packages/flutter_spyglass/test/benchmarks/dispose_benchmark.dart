import 'package:flutter/material.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'bench_stats.dart';
import 'services.dart';

/// Mounts a subtree with [serviceCount] eagerly-created services, then
/// unmounts it and measures teardown cost: removing N InheritedElement
/// subscriptions plus disposing N ChangeNotifiers.
///
/// Note: spyglass's `Deps.dispose()` fires off each dependency's disposal
/// without awaiting it (see `Deps.dispose`/`ManagedDependency.dispose` in
/// package:spyglass - each call is wrapped in `unawaited(...)`), so that
/// work can finish a microtask or two after `dispose()` returns. We pump
/// twice after disposing to let it settle before stopping the clock, for
/// both libraries symmetrically - otherwise this benchmark would make
/// spyglass look faster than it really is by not counting work it deferred.
///
/// Run with: flutter test test/benchmarks/dispose_benchmark.dart
void main() {
  const warmUp = 3;
  const runs = 10;

  testWidgets('Dispose: $serviceCount services', (tester) async {
    Deps? currentDeps;

    final spyglassStats = await runBenchmark(
      warmUpRuns: warmUp,
      measuredRuns: runs,
      setUp: () async {
        final scopeDeps = Deps.root.fork()
          ..addMany([
            for (var i = 0; i < serviceCount; i++) spyglassFactories[i](i),
          ])
          ..ensureResolved(serviceTypes);
        currentDeps = scopeDeps;

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
      },
      body: () async {
        await tester.pumpWidget(const SizedBox());
        await currentDeps!.dispose();
        await tester.pump();
        await tester.pump();
      },
    );

    final providerStats = await runBenchmark(
      warmUpRuns: warmUp,
      measuredRuns: runs,
      setUp: () async {
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
      },
      body: () async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.pump();
      },
    );

    printComparison('Dispose ($serviceCount services)', {
      'spyglass': spyglassStats,
      'provider': providerStats,
    });
  });
}
