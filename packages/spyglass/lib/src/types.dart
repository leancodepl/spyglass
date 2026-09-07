/// The identifier a `Dependency` is registered and looked up by - its
/// runtime `Type`, by default `T` itself (see `Dependency.key`).
typedef DependencyKey = Type;

/// Callback to unregister a dependency. It will be disposed of automatically.
typedef Unregister = void Function();
