import 'package:spyglass/spyglass.dart';

void main() {
  deps.add(Dependency((deps) => ServiceA(deps.get<ServiceB>())));
  deps.add(Dependency((deps) => ServiceB(deps.get<ServiceA>())));

  // This should throw a state error
  deps.get<ServiceA>();
}

class ServiceA {
  ServiceA(this.serviceB);

  final ServiceB serviceB;
}

class ServiceB {
  ServiceB(this.serviceA);

  final ServiceA serviceA;
}
