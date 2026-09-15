import 'package:equatable/equatable.dart';
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

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DepsProvider(
      register: [
        Dependency<AppLocalizations>.value(
            const AppLocalizations(mainPageGreeting: 'Hello world!')),
        Dependency<MainPageLocalizations>(
          (deps, _) => MainPageLocalizations(
            greeting: deps.watchInstance<AppLocalizations>().mainPageGreeting,
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                final greeting =
                    context.watch<MainPageLocalizations>().greeting;

                return Text(greeting);
              },
            ),
          ),
          floatingActionButton: Builder(builder: (context) {
            return FloatingActionButton(
              child: const Icon(Icons.language),
              onPressed: () {
                context.deps.replace(
                  Dependency<AppLocalizations>.value(
                    const AppLocalizations(
                        mainPageGreeting: 'Dla mnie się to podoba!'),
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

class AppLocalizations extends Equatable {
  const AppLocalizations({
    required this.mainPageGreeting,
  });

  final String mainPageGreeting;

  @override
  List<Object?> get props => [mainPageGreeting];
}

class MainPageLocalizations extends Equatable {
  const MainPageLocalizations({
    required this.greeting,
  });

  final String greeting;

  @override
  List<Object?> get props => [greeting];
}
