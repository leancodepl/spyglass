import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Summary statistics over a set of measured [Duration] samples.
class BenchmarkStats {
  BenchmarkStats(List<Duration> samples)
      : samples = List.unmodifiable([...samples]..sort());

  final List<Duration> samples;

  Duration get min => samples.first;
  Duration get max => samples.last;
  Duration get median => samples[samples.length ~/ 2];

  Duration get mean => Duration(
        microseconds: (samples.map((d) => d.inMicroseconds).reduce((a, b) => a + b) /
                samples.length)
            .round(),
      );

  Duration get stdDev {
    final meanUs = mean.inMicroseconds;
    final variance = samples
            .map((d) => math.pow(d.inMicroseconds - meanUs, 2))
            .reduce((a, b) => a + b) /
        samples.length;
    return Duration(microseconds: math.sqrt(variance).round());
  }

  @override
  String toString() =>
      'mean=${_fmt(mean)} median=${_fmt(median)} min=${_fmt(min)} max=${_fmt(max)} '
      'stdDev=${_fmt(stdDev)} (n=${samples.length})';

  static String _fmt(Duration d) => '${(d.inMicroseconds / 1000).toStringAsFixed(2)}ms';
}

/// Runs [body] [warmUpRuns] + [measuredRuns] times, discarding the warm-up
/// runs (JIT/first-frame-cache noise) and returning stats over the rest.
/// [setUp]/[tearDown] run around every iteration, warm-up included.
Future<BenchmarkStats> runBenchmark({
  required Future<void> Function() body,
  Future<void> Function()? setUp,
  Future<void> Function()? tearDown,
  required int warmUpRuns,
  required int measuredRuns,
}) async {
  final sw = Stopwatch();
  final samples = <Duration>[];

  for (var i = 0; i < warmUpRuns + measuredRuns; i++) {
    await setUp?.call();

    sw
      ..reset()
      ..start();
    await body();
    sw.stop();

    if (i >= warmUpRuns) {
      samples.add(sw.elapsed);
    }

    await tearDown?.call();
  }

  return BenchmarkStats(samples);
}

void printComparison(String scenario, Map<String, BenchmarkStats> results) {
  debugPrint('--- $scenario ---');
  for (final entry in results.entries) {
    debugPrint('${entry.key.padRight(10)}: ${entry.value}');
  }
}
