import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';

void main() {
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
          create: (deps) => MainPageLocalizations(
            greeting: deps.get<AppLocalizations>().mainPageGreeting,
          ),
          when: (deps) => deps.watch<AppLocalizations>(),
          update: (deps, oldValue) => MainPageLocalizations(
            greeting: deps.get<AppLocalizations>().mainPageGreeting,
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
