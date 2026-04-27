import 'package:flutter/material.dart';
import 'package:flutter_multi_provider/data_cubit.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';
import 'package:flutter_spyglass_bloc/flutter_spyglass_bloc.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DepsProvider(
      register: [
        Dependency.value('Hello World!'),
        BlocDependency<DataCubit>(
          (_) => DataCubit(),
          dispose: (cubit) => cubit.close(),
        ),
      ],
      child: Builder(builder: (context) {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Builder(
                    builder: (context) {
                      final state = context.observe<DataCubit>().state;
                      final String? stateDescription =
                          switch (state.connectionState) {
                        ConnectionState.none => 'Idle',
                        ConnectionState.waiting => 'Waiting',
                        ConnectionState.active => 'Waiting',
                        ConnectionState.done =>
                          state.hasData ? state.data : state.error.toString(),
                      };

                      return Text('Current status is: $stateDescription');
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context.get<DataCubit>().fetch();
                    },
                    child: const Text('Load data'),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
