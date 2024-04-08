import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';

void main() {
  runApp(const MainApp());
}

final random = Random();

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    const names = [
      'Alan',
      'Beverly',
      'Chris',
      'World',
    ];
    return DepsProvider(
      register: [Dependency.value('Hello World!')],
      child: Builder(builder: (context) {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(context.watch<String>()),
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () {
                final deps = DepsProvider.of(context);
                final name = names[random.nextInt(names.length)];
                deps.add(
                  Dependency.value('Hello $name!'),
                );
              },
              child: const Icon(Icons.shuffle),
            ),
          ),
        );
      }),
    );
  }
}
