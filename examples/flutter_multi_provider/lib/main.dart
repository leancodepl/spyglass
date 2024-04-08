import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart' hide WatchContext;
import 'package:flutter_multi_provider/data_cubit.dart';
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
        Dependency.value('Hello World!'),
        Dependency<DataCubit>(
          create: (_) => DataCubit(),
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
                  BlocBuilder<DataCubit, DataCubitState>(
                    bloc: context.watch(),
                    builder: (context, state) {
                      final stateDescription = switch (state.connectionState) {
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
