import 'package:spyglass/spyglass.dart';
import 'package:test/test.dart';

void main() {
  test('get<TAlias>() and get<TTarget>() return the identical instance', () {
    final scopeDeps = Deps.detached()
      ..addAll([
        Dependency<ServiceImpl>((_, __) => ServiceImpl()),
        const Alias<ServiceInterface, ServiceImpl>(),
      ]);

    expect(
      scopeDeps.get<ServiceInterface>(),
      same(scopeDeps.get<ServiceImpl>()),
    );
  });

  test('the alias is lazy - it does not force early creation', () {
    var created = false;
    final scopeDeps = Deps.detached()
      ..addAll([
        Dependency<ServiceImpl>((_, __) {
          created = true;
          return ServiceImpl();
        }),
        const Alias<ServiceInterface, ServiceImpl>(),
      ]);

    expect(created, isFalse);

    scopeDeps.get<ServiceInterface>();
    expect(created, isTrue);
  });

  test('create() runs exactly once and dispose() runs exactly once, no '
      'matter which key is resolved or removed first', () async {
    var createCalls = 0;
    var disposeCalls = 0;
    final scopeDeps = Deps.detached()
      ..addAll([
        Dependency<ServiceImpl>(
          (_, __) {
            createCalls++;
            return ServiceImpl();
          },
          dispose: (_) => disposeCalls++,
        ),
        const Alias<ServiceInterface, ServiceImpl>(),
      ])
      ..get<ServiceInterface>()
      ..get<ServiceImpl>()
      ..get<ServiceInterface>();
    expect(createCalls, equals(1));

    // Removing just the alias key must not dispose the shared instance -
    // ServiceImpl is still registered and live.
    scopeDeps.remove<ServiceInterface>();
    await Future<void>.delayed(Duration.zero);
    expect(disposeCalls, equals(0));

    scopeDeps.remove<ServiceImpl>();
    await Future<void>.delayed(Duration.zero);
    expect(disposeCalls, equals(1));
  });

  test('the alias follows replace() to the newly-registered instance',
      () async {
    final scopeDeps = Deps.detached()
      ..addAll([
        Dependency<ServiceImpl>((_, __) => ServiceImpl()),
        const Alias<ServiceInterface, ServiceImpl>(),
      ]);

    final first = scopeDeps.get<ServiceInterface>();
    expect(first, same(scopeDeps.get<ServiceImpl>()));

    scopeDeps.replace(Dependency<ServiceImpl>((_, __) => ServiceImpl()));
    await Future<void>.delayed(Duration.zero);

    final second = scopeDeps.get<ServiceInterface>();
    expect(second, isNot(same(first)));
    expect(second, same(scopeDeps.get<ServiceImpl>()));
  });

  test('watch<TAlias>() does not react to internal state changes by '
      'default - TAlias declares nothing about being observable', () async {
    final scopeDeps = Deps.detached()
      ..addAll([
        Dependency<ServiceImpl>(
          (_, __) => ServiceImpl(),
          createObserver: _CounterObserver.new,
        ),
        const Alias<ServiceInterface, ServiceImpl>(),
      ]);

    final events = <ServiceInterface>[];
    final sub = scopeDeps.watch<ServiceInterface>().listen(events.add);
    await Future<void>.delayed(Duration.zero);

    scopeDeps.get<ServiceImpl>().tick();
    await Future<void>.delayed(Duration.zero);

    // Only the initial value - the tick on ServiceImpl never reached the
    // alias's own watch(), since Alias's default createObserver is null.
    expect(events, hasLength(1));

    await sub.cancel();
  });

  test('watch<TAlias>() does react to state changes when an explicit '
      'createObserver is supplied', () async {
    final scopeDeps = Deps.detached()
      ..addAll([
        Dependency<ServiceImpl>((_, __) => ServiceImpl()),
        Alias<ServiceInterface, ServiceImpl>(
          createObserver: (v) => _CounterObserver(v as ServiceImpl),
        ),
      ]);

    final events = <ServiceInterface>[];
    final sub = scopeDeps.watch<ServiceInterface>().listen(events.add);
    await Future<void>.delayed(Duration.zero);

    scopeDeps.get<ServiceImpl>().tick();
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));

    await sub.cancel();
  });

  test(
      'KNOWN CAVEAT: removing only TTarget leaves a stale TAlias entry '
      'behind, pointing at a disposed instance - remove both together '
      'instead', () async {
    var disposeCalls = 0;
    final scopeDeps = Deps.detached()
      ..addAll([
        Dependency<ServiceImpl>(
          (_, __) => ServiceImpl(),
          dispose: (_) => disposeCalls++,
        ),
        const Alias<ServiceInterface, ServiceImpl>(),
      ]);

    final resolved = scopeDeps.get<ServiceInterface>();

    // Bare remove<ServiceImpl>() - not the grouping Module/registerable -
    // disposes the shared instance, but ServiceInterface stays registered
    // and still resolves to it: DependencyUnregistered doesn't retrigger
    // an alias's update().
    scopeDeps.remove<ServiceImpl>();
    await Future<void>.delayed(Duration.zero);

    expect(disposeCalls, equals(1));
    expect(scopeDeps.isRegistered<ServiceInterface>(), isTrue);
    expect(scopeDeps.get<ServiceInterface>(), same(resolved));
  });

  test('removing the Registerable returned by addAll removes both keys '
      'together, avoiding the stale-alias caveat', () {
    final registration = [
      Dependency<ServiceImpl>((_, __) => ServiceImpl()),
      const Alias<ServiceInterface, ServiceImpl>(),
    ];
    final scopeDeps = Deps.detached()
      ..addAll(registration)
      ..get<ServiceInterface>();
    registration.forEach(scopeDeps.remove);

    expect(scopeDeps.isRegistered<ServiceImpl>(), isFalse);
    expect(scopeDeps.isRegistered<ServiceInterface>(), isFalse);
  });

  test('debugOwnDependencies lists the alias under its own key, resolving '
      'to the same value', () {
    final scopeDeps = Deps.detached()
      ..addAll([
        Dependency<ServiceImpl>((_, __) => ServiceImpl()),
        const Alias<ServiceInterface, ServiceImpl>(),
      ]);

    final resolved = scopeDeps.get<ServiceInterface>();

    final byKey = {
      for (final entry in scopeDeps.debugOwnDependencies) entry.key: entry,
    };

    expect(byKey.keys, containsAll(<Type>[ServiceImpl, ServiceInterface]));
    expect(byKey[ServiceInterface]!.value, same(resolved));
  });
}

/// A [DependencyObserver] over the concrete [ServiceImpl] - usable directly
/// as `Dependency<ServiceImpl>.createObserver`, and (cast at the call site,
/// same as `Alias` itself has to) as `Alias<..>.createObserver` too, since
/// [DependencyObserver] is covariant: a `DependencyObserver<ServiceImpl>`
/// works wherever `DependencyObserver<ServiceInterface>` is expected.
class _CounterObserver extends DependencyObserver<ServiceImpl> {
  _CounterObserver(this.service) {
    service.addListener(_onChange);
  }

  final ServiceImpl service;

  void _onChange() => notifyStateChanged();

  @override
  Future<void> dispose() async => service.removeListener(_onChange);
}

abstract class ServiceInterface {
  void tick();
}

class ServiceImpl implements ServiceInterface {
  final List<void Function()> _listeners = [];

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) =>
      _listeners.remove(listener);

  @override
  void tick() {
    for (final listener in [..._listeners]) {
      listener();
    }
  }
}
