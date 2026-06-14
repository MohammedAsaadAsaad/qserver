/// The heart of dependency injection in Quds Server
class QudsContainer {
  static final Map<Type, dynamic> _singletons = {};
  static final Map<Type, Function> _factories = {};

  /// Binds an instance as a Singleton.
  /// The same exact instance will be returned every time it is resolved.
  static void singleton<T>(T instance) {
    _singletons[T] = instance;
  }

  /// Binds a factory builder.
  /// A brand new instance will be created every time it is resolved.
  static void bind<T>(T Function() builder) {
    _factories[T] = builder;
  }

  /// Resolves the requested type from the container.
  static T resolve<T>() {
    if (_singletons.containsKey(T)) {
      return _singletons[T] as T;
    }

    if (_factories.containsKey(T)) {
      return _factories[T]!() as T;
    }

    throw Exception(
      "QudsContainer Error: Dependency of type $T not found. "
      "Ensure it is registered in a ServiceProvider.",
    );
  }

  /// Clears the container (useful for tearing down tests)
  static void clear() {
    _singletons.clear();
    _factories.clear();
  }
}

/// Global helper function mirroring Laravel's app() helper
T app<T>() => QudsContainer.resolve<T>();
