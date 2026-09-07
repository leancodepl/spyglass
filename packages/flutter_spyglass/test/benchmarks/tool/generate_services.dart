// Generates services.dart. Dart generics need a static type per registered
// dependency, so getting N genuinely distinct, independently-retrievable
// spyglass/provider entries means N genuinely distinct classes - there's no
// way to fake that with a loop at the call site. Regenerate with:
//   dart run test/benchmarks/tool/generate_services.dart > test/benchmarks/services.dart
import 'dart:io';

const serviceCount = 100;

void main() {
  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE - do not edit by hand.')
    ..writeln(
      '// Regenerate with: dart run test/benchmarks/tool/generate_services.dart > test/benchmarks/services.dart',
    )
    ..writeln("import 'package:flutter/widgets.dart';")
    ..writeln("import 'package:flutter_spyglass/flutter_spyglass.dart';")
    ..writeln("import 'package:nested/nested.dart' show SingleChildWidget;")
    ..writeln("import 'package:provider/provider.dart';")
    ..writeln()
    ..writeln('const serviceCount = $serviceCount;')
    ..writeln()
    ..writeln('/// Number of times the leaf at index i has rebuilt since the')
    ..writeln(
        '/// last [resetBuildCounts] call. Used to verify that mutating one')
    ..writeln('/// service only rebuilds the widget(s) observing it.')
    ..writeln('final List<int> buildCounts = List.filled(serviceCount, 0);')
    ..writeln()
    ..writeln('void resetBuildCounts() {')
    ..writeln('  buildCounts.fillRange(0, serviceCount, 0);')
    ..writeln('}')
    ..writeln()
    ..writeln('/// Common shape so the benchmark driver can mutate whichever')
    ..writeln('/// service it looked up by index without per-index casts.')
    ..writeln('abstract class MutableService extends ChangeNotifier {')
    ..writeln('  int get value;')
    ..writeln('  void update(int value);')
    ..writeln('}')
    ..writeln();

  for (var i = 0; i < serviceCount; i++) {
    buffer.writeln(
      'class Svc$i extends MutableService { '
      'Svc$i(this._value); int _value; '
      '@override int get value => _value; '
      '@override void update(int v) { _value = v; notifyListeners(); } '
      '}',
    );
  }

  buffer
    ..writeln()
    ..writeln('final List<Type> serviceTypes = [')
    ..writeln([for (var i = 0; i < serviceCount; i++) '  Svc$i,'].join('\n'))
    ..writeln('];')
    ..writeln()
    ..writeln(
      'final List<Dependency<Object> Function(int value)> spyglassFactories = [',
    );
  for (var i = 0; i < serviceCount; i++) {
    buffer.writeln(
        '  (v) => ChangeNotifierDependency<Svc$i>((_, __) => Svc$i(v)),');
  }

  buffer
    ..writeln('];')
    ..writeln()
    ..writeln('final List<Widget Function(BuildContext)> spyglassReaders = [');
  for (var i = 0; i < serviceCount; i++) {
    buffer.writeln(
      '  (c) { buildCounts[$i]++; return Text(DepsContext(c).watch<Svc$i>().value.toString()); },',
    );
  }

  buffer
    ..writeln('];')
    ..writeln()
    ..writeln('final List<MutableService Function(Deps)> spyglassGetters = [');
  for (var i = 0; i < serviceCount; i++) {
    buffer.writeln('  (d) => d.get<Svc$i>(),');
  }

  buffer
    ..writeln('];')
    ..writeln()
    ..writeln(
      'final List<SingleChildWidget Function(int value)> providerFactories = [',
    );
  for (var i = 0; i < serviceCount; i++) {
    buffer.writeln(
      '  (v) => ChangeNotifierProvider<Svc$i>(create: (_) => Svc$i(v), lazy: false),',
    );
  }

  buffer
    ..writeln('];')
    ..writeln()
    ..writeln('final List<Widget Function(BuildContext)> providerReaders = [');
  for (var i = 0; i < serviceCount; i++) {
    buffer.writeln(
      '  (c) { buildCounts[$i]++; return Text(WatchContext(c).watch<Svc$i>().value.toString()); },',
    );
  }

  buffer
    ..writeln('];')
    ..writeln()
    ..writeln(
      'final List<MutableService Function(BuildContext)> providerGetters = [',
    );
  for (var i = 0; i < serviceCount; i++) {
    buffer.writeln('  (c) => ReadContext(c).read<Svc$i>(),');
  }

  buffer
    ..writeln('];')
    ..writeln()
    ..writeln('/// Plain, non-reactive reads - never calls observe()/watch(),')
    ..writeln(
        '/// so on the spyglass side no DependencyObserver/BehaviorSubject')
    ..writeln('/// is ever created for these services (see ManagedDependency).')
    ..writeln(
      'final List<Widget Function(BuildContext)> spyglassNonReactiveReaders = [',
    );
  for (var i = 0; i < serviceCount; i++) {
    buffer.writeln(
      '  (c) { buildCounts[$i]++; return Text(c.get<Svc$i>().value.toString()); },',
    );
  }

  buffer
    ..writeln('];')
    ..writeln()
    ..writeln(
      'final List<Widget Function(BuildContext)> providerNonReactiveReaders = [',
    );
  for (var i = 0; i < serviceCount; i++) {
    buffer.writeln(
      '  (c) { buildCounts[$i]++; return Text(ReadContext(c).read<Svc$i>().value.toString()); },',
    );
  }
  buffer.writeln('];');

  stdout.write(buffer.toString());
}
