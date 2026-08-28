import 'package:flutter/foundation.dart';
import 'package:spyglass/spyglass.dart';

/// Turns a [Deps] scope into something Flutter's diagnostics tooling can
/// display - the widget inspector, `debugDumpApp()`-style tools, or just
/// `debugPrint(deps.toDiagnosticsNode().toStringDeep())` for a quick dump
/// from anywhere.
extension DepsDiagnosticsTree on Deps {
  /// A [DiagnosticsNode] for this scope: its own registered dependencies as
  /// children (see [Deps.debugOwnDependencies]) plus, when
  /// [spyglassDiagnosticsMode] is enabled, every descendant scope created
  /// via [Deps.fork] (see [Deps.debugChildren]), each nested the same way.
  ///
  /// With diagnostics mode disabled, only this single scope's own
  /// dependencies are shown - a note on the node says so.
  DiagnosticsNode toDiagnosticsNode({String? name}) =>
      _DepsDiagnosticableTree(this).toDiagnosticsNode(name: name);
}

class _DepsDiagnosticableTree extends DiagnosticableTree {
  const _DepsDiagnosticableTree(this.deps);

  final Deps deps;

  @override
  String toStringShort() => deps.toString();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      FlagProperty('disposed', value: deps.isDisposed, ifTrue: 'disposed'),
    );
    if (!spyglassDiagnosticsMode) {
      properties.add(
        MessageProperty(
          'note',
          'child scopes hidden - run with '
              '--dart-define=spyglass.diagnosticsMode=true to include them',
        ),
      );
    }
  }

  @override
  List<DiagnosticsNode> debugDescribeChildren() => [
        for (final entry in deps.debugOwnDependencies)
          _DependencyDiagnosticableTree(entry).toDiagnosticsNode(),
        for (final child in deps.debugChildren)
          _DepsDiagnosticableTree(child).toDiagnosticsNode(name: 'child scope'),
      ];
}

class _DependencyDiagnosticableTree extends DiagnosticableTree {
  const _DependencyDiagnosticableTree(this.entry);

  final DependencyDiagnostics entry;

  @override
  String toStringShort() => entry.dependency.toString();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      FlagProperty(
        'resolved',
        value: entry.isResolved,
        ifTrue: 'resolved',
        ifFalse: 'not yet resolved',
      ),
    );
    if (entry.isResolved) {
      properties.add(DiagnosticsProperty('value', entry.value));
    }
    properties.add(
      FlagProperty(
        'standalone',
        value: entry.isStandalone,
        ifTrue: 'standalone',
        ifFalse: 'part of ${entry.module ?? entry.origin}',
      ),
    );
    if (entry.dependency.tags case final tags? when tags.isNotEmpty) {
      properties.add(IterableProperty('tags', tags));
    }
  }

  @override
  List<DiagnosticsNode> debugDescribeChildren() => const [];
}
