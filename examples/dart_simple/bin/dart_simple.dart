import 'package:spyglass/spyglass.dart';

void main() {
  deps.add(Dependency.value(Greeter()));

  final greeter = deps.get<Greeter>();

  greeter.greet();
}

class Greeter {
  void greet() {
    print('Hello world!');
  }
}
