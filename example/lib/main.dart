import 'package:flutter/material.dart';
import 'package:spyglass/spyglass.dart';

void main() {
  Deps.root.register(Dependency<int>(
    create: (scope) => 5,
    key: 'a',
  ));
  Deps.root.register(Dependency<int>(
    create: (scope) => 5 + scope.get('a'),
    key: 'b',
  ));
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DepsProvider(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            final a = DepsProvider.watch<int>(
              context,
              key: 'a',
            );

            return Center(
              child: Text('Hello World! $a'),
            );
          }),
          floatingActionButton: Builder(builder: (context) {
            return FloatingActionButton(
              onPressed: () {
                final deps = DepsProvider.of(context);
                final previous = deps.get<int>('a');
                deps.register(
                  Dependency<int>(
                    create: (deps) => previous + 1,
                    key: 'a',
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}
