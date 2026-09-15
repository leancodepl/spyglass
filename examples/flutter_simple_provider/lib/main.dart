import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  // Lets an MCP client (e.g. marionette_mcp) inspect and drive this app at
  // runtime - inert in release builds.
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
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
      register: [
        Dependency<String>.value('Hello World!'),
      ],
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
