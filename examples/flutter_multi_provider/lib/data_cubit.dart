import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef DataCubitState = AsyncSnapshot<String>;

class DataCubit extends Cubit<DataCubitState> {
  DataCubit() : super(const AsyncSnapshot<String>.nothing());

  final _random = Random();

  Future<void> fetch() async {
    if (state.connectionState == ConnectionState.waiting) {
      return;
    }

    emit(const AsyncSnapshot<String>.waiting());
    await Future<void>.delayed(const Duration(seconds: 2));

    final success = _random.nextBool();

    if (success) {
      emit(const AsyncSnapshot<String>.withData(
          ConnectionState.done, 'Success!'));
    } else {
      emit(const AsyncSnapshot<String>.withError(
          ConnectionState.done, 'Failed to fetch data'));
    }
  }
}
