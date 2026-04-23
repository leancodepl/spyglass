import 'package:spyglass/spyglass.dart';

class MyGlobalScope extends DiscoScope with AuthModule<MyGlobalScope> {
  MyGlobalScope({
    super.parent,
  });

  late final foo =
      singleton<Foo, MyGlobalScope>(DiscoDep<Foo>(Foo.new, key: 'foo'));
  late final bar = singleton<Bar, MyGlobalScope>(
      DiscoDep<Bar>(() => Bar(foo: foo()), key: 'bar'));
}

mixin AuthModule<TScope extends DiscoScope> on DiscoScope {
  late final authService = singleton<AuthService, TScope>(
      DiscoDep<AuthService>(AuthService.new, key: 'authService'));
}

class MyFeatureScope extends MyGlobalScope {
  MyFeatureScope({
    required MyGlobalScope super.parent,
  });

  late final baz = singleton<Baz, MyFeatureScope>(
      DiscoDep<Baz>(() => Baz(foo: foo()), key: 'baz'));
  late final qux =
      singleton<Qux, MyFeatureScope>(DiscoDep<Qux>(Qux.new, key: 'qux'));
}

class AuthService {
  AuthService();
}

class Foo {}

class Bar {
  Bar({
    required this.foo,
  });

  final Foo foo;
}

class Baz {
  Baz({
    required this.foo,
  });

  final Foo foo;
}

class Qux {}

void main() {
  final globalScope = MyGlobalScope();
  final featureScope = MyFeatureScope(parent: globalScope);

  final foo = globalScope.foo();
  final bar = globalScope.bar();
  final authService = globalScope.authService();

  final baz = featureScope.baz();
  final qux = featureScope.qux();
  final featureFoo = featureScope.foo();
  final featureBar = featureScope.bar();
  final featureAuthService = featureScope.authService();

  print(foo);
  print(bar);
  print(authService);
  print(baz);
  print(qux);
  print(featureFoo);
  print(featureBar);
  print(featureAuthService);
}
