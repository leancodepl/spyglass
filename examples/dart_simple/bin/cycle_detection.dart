import 'package:spyglass/spyglass.dart';

void main() {
  Deps.global.add(Dependency((deps, _) => ServiceA(deps.get<ServiceB>())));
  Deps.global.add(Dependency((deps, _) => ServiceB(deps.get<ServiceA>())));

  // This should throw a state error
  Deps.global.get<ServiceA>();
}

class ServiceA {
  ServiceA(this.serviceB);

  final ServiceB serviceB;
}

class ServiceB {
  ServiceB(this.serviceA);

  final ServiceA serviceA;
}
